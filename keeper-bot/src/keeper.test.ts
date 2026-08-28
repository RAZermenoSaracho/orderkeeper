import { beforeEach, describe, expect, test, vi } from "vitest";
import { ContractFunctionRevertedError, encodeErrorResult, type Address } from "viem";
import { orderKeeperAbi } from "./abi.js";

// keeper.ts imports publicClient/walletClient/operatorAccount directly from
// chain.js at module scope, and chain.js throws at import time if
// RPC_URL/PRIVATE_KEY aren't set — neither is set in a test environment, so
// chain.js must be fully mocked, not just its exports stubbed after import.
const mockReadContract = vi.fn();
const mockWriteContract = vi.fn();
vi.mock("./chain.js", () => ({
  publicClient: { readContract: (...args: unknown[]) => mockReadContract(...args) },
  walletClient: { writeContract: (...args: unknown[]) => mockWriteContract(...args) },
  operatorAccount: { address: "0x0000000000000000000000000000000000000001" },
}));

const mockFetchPendingOrders = vi.fn();
vi.mock("./indexerClient.js", () => ({
  fetchPendingOrders: (...args: unknown[]) => mockFetchPendingOrders(...args),
}));

const { runPollCycle } = await import("./keeper.js");

const ORDER_KEEPER_ADDRESS: Address = "0x2d065b6a75A207e73Cc9f76953A5886B250336FD";
const INDEXER_URL = "http://localhost:3001";

// Builds a real ContractFunctionRevertedError decoding to the given custom
// error name, the same shape viem actually throws from writeContract() —
// exercises extractRevertReason()'s real ABI-decoding path rather than a
// hand-faked shortcut.
function makeRevertError(errorName: string, args: readonly unknown[] = []): ContractFunctionRevertedError {
  // errorName/args are deliberately dynamic here (parameterized across
  // several different error shapes in the tests below) — narrower than
  // encodeErrorResult's per-error-name overloads, hence the cast.
  const data = encodeErrorResult({ abi: orderKeeperAbi, errorName, args } as Parameters<typeof encodeErrorResult>[0]);
  return new ContractFunctionRevertedError({ abi: orderKeeperAbi, data, functionName: "executeOrder" });
}

beforeEach(() => {
  mockReadContract.mockReset();
  mockWriteContract.mockReset();
  mockFetchPendingOrders.mockReset();
});

describe("runPollCycle", () => {
  test("does nothing when order-indexer returns no pending orders", async () => {
    mockFetchPendingOrders.mockResolvedValue([]);

    await runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL);

    expect(mockReadContract).not.toHaveBeenCalled();
    expect(mockWriteContract).not.toHaveBeenCalled();
  });

  test("logs and returns without throwing when order-indexer is unreachable", async () => {
    mockFetchPendingOrders.mockRejectedValue(new Error("fetch failed"));

    await expect(runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL)).resolves.toBeUndefined();
    expect(mockReadContract).not.toHaveBeenCalled();
  });

  test("does not call executeOrder when checkPriceCondition returns false", async () => {
    mockFetchPendingOrders.mockResolvedValue([{ orderId: 1 }]);
    mockReadContract.mockResolvedValue(false);

    await runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL);

    expect(mockReadContract).toHaveBeenCalledOnce();
    expect(mockWriteContract).not.toHaveBeenCalled();
  });

  test("calls executeOrder with the order id as a bigint when checkPriceCondition returns true", async () => {
    mockFetchPendingOrders.mockResolvedValue([{ orderId: 42 }]);
    mockReadContract.mockResolvedValue(true);
    mockWriteContract.mockResolvedValue("0xhash");

    await runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL);

    expect(mockWriteContract).toHaveBeenCalledOnce();
    expect(mockWriteContract).toHaveBeenCalledWith(
      expect.objectContaining({ functionName: "executeOrder", args: [42n] }),
    );
  });

  test("processes multiple pending orders sequentially (not concurrently)", async () => {
    const callOrder: number[] = [];
    mockFetchPendingOrders.mockResolvedValue([{ orderId: 1 }, { orderId: 2 }]);
    mockReadContract.mockImplementation(async ({ args }: { args: [bigint] }) => {
      callOrder.push(Number(args[0]));
      return true;
    });
    mockWriteContract.mockResolvedValue("0xhash");

    await runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL);

    expect(callOrder).toEqual([1, 2]);
    expect(mockWriteContract).toHaveBeenCalledTimes(2);
  });

  test("continues to the next order when checkPriceCondition throws for one order", async () => {
    mockFetchPendingOrders.mockResolvedValue([{ orderId: 1 }, { orderId: 2 }]);
    mockReadContract.mockRejectedValueOnce(new Error("RPC timeout")).mockResolvedValueOnce(true);
    mockWriteContract.mockResolvedValue("0xhash");

    await runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL);

    expect(mockReadContract).toHaveBeenCalledTimes(2);
    expect(mockWriteContract).toHaveBeenCalledTimes(1);
  });

  test.each(["ConditionNotMet", "OrderNotPending", "OrderExpired", "OrderNotFound"])(
    "swallows an expected race revert (%s) without throwing",
    async (errorName) => {
      mockFetchPendingOrders.mockResolvedValue([{ orderId: 1 }]);
      mockReadContract.mockResolvedValue(true);
      const args = errorName === "OrderNotPending" ? [1n, 1] : errorName === "OrderExpired" ? [1n, 0n] : [1n];
      mockWriteContract.mockRejectedValue(makeRevertError(errorName, args));

      await expect(runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL)).resolves.toBeUndefined();
    },
  );

  test("does not throw on an unexpected revert reason either — logged, not rethrown", async () => {
    mockFetchPendingOrders.mockResolvedValue([{ orderId: 1 }]);
    mockReadContract.mockResolvedValue(true);
    mockWriteContract.mockRejectedValue(makeRevertError("InvalidPrice"));

    await expect(runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL)).resolves.toBeUndefined();
  });

  test("does not throw on a completely generic (non-viem) error from writeContract", async () => {
    mockFetchPendingOrders.mockResolvedValue([{ orderId: 1 }]);
    mockReadContract.mockResolvedValue(true);
    mockWriteContract.mockRejectedValue(new Error("network hiccup"));

    await expect(runPollCycle(ORDER_KEEPER_ADDRESS, INDEXER_URL)).resolves.toBeUndefined();
  });
});
