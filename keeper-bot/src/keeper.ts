import { BaseError, ContractFunctionRevertedError, type Address } from "viem";
import { publicClient, walletClient, operatorAccount } from "./chain.js";
import { orderKeeperAbi } from "./abi.js";
import { fetchPendingOrders } from "./indexerClient.js";

// Reverts expected from the checkPriceCondition()-then-executeOrder() race:
// the price can move back, the order can expire, or — since executeOrder()
// is permissionless by design — another caller can execute it first, all
// in the moments between our read and our write landing. None of these are
// bugs; executeOrder() reverting leaves the order Pending (see
// contracts/src/OrderKeeper.sol), so the next poll cycle naturally
// re-evaluates it. No special retry logic needed.
const EXPECTED_RACE_ERRORS = new Set(["ConditionNotMet", "OrderNotPending", "OrderExpired", "OrderNotFound"]);

/// Runs one poll cycle: fetches pending orders from order-indexer, and for
/// each, re-checks the price condition on-chain (never trusting the
/// indexer's snapshot as authorization to execute) before sending
/// executeOrder(). Orders are processed sequentially, not in parallel —
/// concurrent sends from the same operator account risk nonce collisions.
export async function runPollCycle(orderKeeperAddress: Address, indexerUrl: string): Promise<void> {
  let pendingOrders: Awaited<ReturnType<typeof fetchPendingOrders>>;
  try {
    pendingOrders = await fetchPendingOrders(indexerUrl);
  } catch (error) {
    console.error("[keeper-bot] Failed to fetch pending orders from order-indexer:", error);
    return;
  }

  for (const order of pendingOrders) {
    await checkAndExecute(orderKeeperAddress, order.orderId);
  }
}

async function checkAndExecute(orderKeeperAddress: Address, orderId: number): Promise<void> {
  let met: boolean;
  try {
    met = await publicClient.readContract({
      address: orderKeeperAddress,
      abi: orderKeeperAbi,
      functionName: "checkPriceCondition",
      args: [BigInt(orderId)],
    });
  } catch (error) {
    console.error(`[keeper-bot] checkPriceCondition(${orderId}) failed:`, error);
    return;
  }

  if (!met) return;

  try {
    // writeContract simulates before broadcasting, so most races here are
    // caught before any gas is spent — but the same handling applies
    // whether the revert comes from that simulation or from a real mined
    // transaction.
    const hash = await walletClient.writeContract({
      address: orderKeeperAddress,
      abi: orderKeeperAbi,
      functionName: "executeOrder",
      args: [BigInt(orderId)],
      account: operatorAccount,
    });
    console.log(`[keeper-bot] executeOrder(${orderId}) submitted: ${hash}`);
  } catch (error) {
    logExecutionFailure(orderId, error);
  }
}

function logExecutionFailure(orderId: number, error: unknown): void {
  const reason = extractRevertReason(error);

  if (reason && EXPECTED_RACE_ERRORS.has(reason)) {
    console.info(`[keeper-bot] executeOrder(${orderId}) reverted (${reason}) — expected race, retrying next cycle.`);
  } else {
    console.error(`[keeper-bot] executeOrder(${orderId}) failed unexpectedly:`, error);
  }
}

function extractRevertReason(error: unknown): string | undefined {
  if (!(error instanceof BaseError)) return undefined;

  const revertError = error.walk((err) => err instanceof ContractFunctionRevertedError);
  if (revertError instanceof ContractFunctionRevertedError) {
    return revertError.data?.errorName;
  }

  return undefined;
}
