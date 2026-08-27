import type { Address } from "viem";
import { HttpRequestError } from "viem";
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

// eth_getLogs block-range limit per call, chunked to stay under it during
// backfill. Discovered the hard way: Alchemy's free tier caps eth_getLogs
// at a 10-block range — a single unchunked call across any gap wider than
// that (e.g. after the indexer has been down for a while) fails outright.
// Overridable via env for providers with a larger (or no) limit; 10 is the
// safe default. Live watching (below) isn't affected in normal operation —
// each poll only spans the tiny gap since the last poll — but if the
// process stalls without restarting for long enough to reopen a similar
// gap, that single poll could still hit the same limit; watchContractEvent
// logs it via onError rather than crashing, and picks back up next poll.
const GETLOGS_BLOCK_RANGE = BigInt(process.env.GETLOGS_BLOCK_RANGE ?? 10);

// Proactive throttle between backfill chunks, on top of chain.ts's
// per-request 429 retry/backoff: with a large gap (thousands of chunks),
// firing eth_getLogs calls back-to-back with zero spacing trips a
// free-tier rate limit long before any individual call is slow enough to
// need retrying. This isn't a substitute for that retry — it just reduces
// how often backfill needs it in the first place. Overridable via env for
// providers with a higher (or no) rate limit; 0 disables it.
const BACKFILL_DELAY_MS = Number(process.env.BACKFILL_DELAY_MS ?? 200);

/// Starts the indexer: backfills any blocks missed since the last
/// checkpoint (or, on a truly fresh install with no checkpoint, starts
/// from the current block — this does not retroactively backfill full
/// contract history from deployment, only resumes across restarts), then
/// watches for new events indefinitely.
export async function startIndexer(orderKeeperAddress: Address): Promise<void> {
  console.log("Fetching current block from RPC...");
  const currentBlock = await publicClient.getBlockNumber();
  console.log(`Current block: ${currentBlock}`);

  const checkpoint = await prisma.indexerState.findUnique({ where: { id: CHECKPOINT_ID } });
  const fromBlock = checkpoint ? checkpoint.lastProcessedBlock + 1n : currentBlock;
  console.log(
    checkpoint
      ? `Resuming from checkpoint: last processed block ${checkpoint.lastProcessedBlock}`
      : "No checkpoint found — starting from the current block (no historical backfill).",
  );

  if (fromBlock <= currentBlock) {
    console.log(`Backfilling ${currentBlock - fromBlock + 1n} blocks (${fromBlock} to ${currentBlock})...`);
    await backfill(orderKeeperAddress, fromBlock, currentBlock);
    console.log("Backfill complete.");
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
  console.log("Watching for new OrderKeeper events...");
}

// Progress is logged for the first chunk immediately, then periodically —
// not every chunk, since a large gap can mean thousands of them — so a
// long backfill never goes more than a few seconds without visible output.
const PROGRESS_LOG_EVERY_N_CHUNKS = 25;

async function backfill(orderKeeperAddress: Address, fromBlock: bigint, toBlock: bigint): Promise<void> {
  let chunkIndex = 0;
  for (let chunkStart = fromBlock; chunkStart <= toBlock; chunkStart += GETLOGS_BLOCK_RANGE) {
    const chunkEndCandidate = chunkStart + GETLOGS_BLOCK_RANGE - 1n;
    const chunkEnd = chunkEndCandidate > toBlock ? toBlock : chunkEndCandidate;
    chunkIndex++;

    const logs = await getLogsChunk(orderKeeperAddress, chunkStart, chunkEnd);
    if (logs.length > 0) {
      console.log(`Backfill: blocks ${chunkStart}-${chunkEnd} — found ${logs.length} event(s)`);
    }

    for (const log of sortLogs(logs as unknown as OrderKeeperLog[])) {
      await processLog(log);
    }

    // Advanced per chunk, not just once at the end: if the process is
    // interrupted mid-backfill, it resumes from the last completed chunk
    // instead of redoing the whole gap.
    await advanceCheckpoint(chunkEnd);

    if (chunkIndex === 1 || chunkIndex % PROGRESS_LOG_EVERY_N_CHUNKS === 0 || chunkEnd === toBlock) {
      console.log(`Backfill progress: block ${chunkEnd}/${toBlock} (${toBlock - chunkEnd} blocks remaining)`);
    }

    if (BACKFILL_DELAY_MS > 0 && chunkEnd < toBlock) {
      await sleep(BACKFILL_DELAY_MS);
    }
  }
}

// Wraps getLogs so an exhausted 429 retry (chain.ts already retries the
// request itself with exponential backoff) surfaces as an actionable error
// naming the failed range, rather than viem's generic HttpRequestError.
async function getLogsChunk(orderKeeperAddress: Address, fromBlock: bigint, toBlock: bigint) {
  try {
    return await publicClient.getLogs({
      address: orderKeeperAddress,
      events: orderKeeperEventsAbi,
      fromBlock,
      toBlock,
    });
  } catch (error) {
    if (error instanceof HttpRequestError && error.status === 429) {
      throw new Error(
        `Backfill's eth_getLogs for blocks ${fromBlock}-${toBlock} kept hitting ` +
          `429 Too Many Requests even after retrying with backoff (see chain.ts). ` +
          `The RPC provider's rate limit is too low for this backfill gap — try a ` +
          `higher BACKFILL_DELAY_MS, a paid RPC tier, or narrowing the gap by ` +
          `restarting the indexer more often.`,
        { cause: error },
      );
    }
    throw error;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

    await advanceCheckpoint(log.blockNumber);
  } catch (error) {
    // Logged, not thrown — one malformed/out-of-order log, or a transient
    // DB failure on either the handler or the checkpoint update, shouldn't
    // take down the whole indexer loop (and shouldn't surface as an
    // unhandled promise rejection either).
    console.error(`Failed to process ${log.eventName} at block ${log.blockNumber}, tx ${log.transactionHash}:`, error);
  }
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
