import type { Address } from "viem";
import { publicClient } from "./chain.js";
import { prisma } from "./db.js";
import { orderKeeperEventsAbi } from "./abi.js";

// A minimal shape for what this module actually reads off a decoded log —
// rather than hand-replicating viem's full Log<> generic signature (which
// varies by call site: watchContractEvent's onLogs vs getLogs's return
// type are structurally identical but not the same TS type). Both real
// call sites below satisfy this shape; args is validated at the point
// each handler destructures it.
interface OrderKeeperLog {
  eventName: "OrderCreated" | "OrderExecuted" | "OrderCancelled";
  blockNumber: bigint;
  transactionHash: `0x${string}`;
  logIndex: number;
  args: Record<string, unknown>;
}

const CHECKPOINT_ID = 1;

/// Starts the indexer: backfills any blocks missed since the last
/// checkpoint (or, on a truly fresh install with no checkpoint, starts
/// from the current block — this does not retroactively backfill full
/// contract history from deployment, only resumes across restarts), then
/// watches for new events indefinitely.
export async function startIndexer(orderKeeperAddress: Address): Promise<void> {
  const currentBlock = await publicClient.getBlockNumber();
  const checkpoint = await prisma.indexerState.findUnique({ where: { id: CHECKPOINT_ID } });
  const fromBlock = checkpoint ? checkpoint.lastProcessedBlock + 1n : currentBlock;

  if (fromBlock <= currentBlock) {
    await backfill(orderKeeperAddress, fromBlock, currentBlock);
  }

  publicClient.watchContractEvent({
    address: orderKeeperAddress,
    abi: orderKeeperEventsAbi,
    onLogs: async (logs) => {
      for (const log of sortLogs(logs as unknown as OrderKeeperLog[])) {
        await processLog(log);
      }
    },
    onError: (error) => {
      console.error("watchContractEvent error:", error);
    },
  });
}

async function backfill(orderKeeperAddress: Address, fromBlock: bigint, toBlock: bigint): Promise<void> {
  const logs = await publicClient.getLogs({
    address: orderKeeperAddress,
    events: orderKeeperEventsAbi,
    fromBlock,
    toBlock,
  });

  for (const log of sortLogs(logs as unknown as OrderKeeperLog[])) {
    await processLog(log);
  }

  await advanceCheckpoint(toBlock);
}

function sortLogs(logs: OrderKeeperLog[]): OrderKeeperLog[] {
  return [...logs].sort((a, b) => {
    if (a.blockNumber !== b.blockNumber) return a.blockNumber < b.blockNumber ? -1 : 1;
    return a.logIndex - b.logIndex;
  });
}

async function processLog(log: OrderKeeperLog): Promise<void> {
  try {
    switch (log.eventName) {
      case "OrderCreated":
        await handleOrderCreated(log);
        break;
      case "OrderExecuted":
        await handleOrderExecuted(log);
        break;
      case "OrderCancelled":
        await handleOrderCancelled(log);
        break;
    }
  } catch (error) {
    // Logged, not thrown — one malformed/out-of-order log shouldn't take
    // down the whole indexer loop.
    console.error(`Failed to process ${log.eventName} at block ${log.blockNumber}, tx ${log.transactionHash}:`, error);
    return;
  }

  await advanceCheckpoint(log.blockNumber);
}

async function handleOrderCreated(log: OrderKeeperLog): Promise<void> {
  const { orderId, owner, asset, condition, targetPrice, amount, maxSlippageBps, expiry } = log.args as {
    orderId: bigint;
    owner: Address;
    asset: Address;
    condition: number;
    targetPrice: bigint;
    amount: bigint;
    maxSlippageBps: bigint;
    expiry: bigint;
  };

  await prisma.order.upsert({
    where: { orderId: Number(orderId) },
    create: {
      orderId: Number(orderId),
      owner,
      asset,
      condition: condition === 0 ? "GreaterOrEqual" : "LessOrEqual",
      targetPrice: targetPrice.toString(),
      amount: amount.toString(),
      maxSlippageBps: Number(maxSlippageBps),
      expiry: new Date(Number(expiry) * 1000),
      status: "Pending",
      createdAtBlock: log.blockNumber,
      createdAtTx: log.transactionHash,
    },
    // Idempotent: re-processing the same log after a restart (backfill
    // overlap) must not clobber whatever's already there.
    update: {},
  });
}

async function handleOrderExecuted(log: OrderKeeperLog): Promise<void> {
  const { orderId, executionPrice, keeperFee, amountOut } = log.args as {
    orderId: bigint;
    executor: Address;
    executionPrice: bigint;
    keeperFee: bigint;
    amountOut: bigint;
  };

  await prisma.order.update({
    where: { orderId: Number(orderId) },
    data: {
      status: "Executed",
      executedAtBlock: log.blockNumber,
      executedAtTx: log.transactionHash,
      executionPrice: executionPrice.toString(),
      keeperFee: keeperFee.toString(),
      amountOut: amountOut.toString(),
    },
  });
}

async function handleOrderCancelled(log: OrderKeeperLog): Promise<void> {
  const { orderId } = log.args as { orderId: bigint; owner: Address; refundAmount: bigint };

  await prisma.order.update({
    where: { orderId: Number(orderId) },
    data: {
      status: "Cancelled",
      cancelledAtBlock: log.blockNumber,
      cancelledAtTx: log.transactionHash,
    },
  });
}

async function advanceCheckpoint(blockNumber: bigint): Promise<void> {
  const state = await prisma.indexerState.findUnique({ where: { id: CHECKPOINT_ID } });
  if (state && blockNumber <= state.lastProcessedBlock) return;

  await prisma.indexerState.upsert({
    where: { id: CHECKPOINT_ID },
    create: { id: CHECKPOINT_ID, lastProcessedBlock: blockNumber },
    update: { lastProcessedBlock: blockNumber },
  });
}
