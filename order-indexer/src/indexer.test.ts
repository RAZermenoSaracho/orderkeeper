import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

process.env.BACKFILL_DELAY_MS = "0";

const mockGetBlockNumber = vi.fn();
const mockGetLogs = vi.fn();
const mockStateFindUnique = vi.fn();
const mockStateUpsert = vi.fn();
const mockOrderUpsert = vi.fn();
const mockOrderUpdate = vi.fn();

vi.mock("./chain.js", () => ({
  publicClient: {
    getBlockNumber: (...args: unknown[]) => mockGetBlockNumber(...args),
    getLogs: (...args: unknown[]) => mockGetLogs(...args),
  },
}));

vi.mock("./db.js", () => ({
  prisma: {
    indexerState: {
      findUnique: (...args: unknown[]) => mockStateFindUnique(...args),
      upsert: (...args: unknown[]) => mockStateUpsert(...args),
    },
    order: {
      upsert: (...args: unknown[]) => mockOrderUpsert(...args),
      update: (...args: unknown[]) => mockOrderUpdate(...args),
    },
  },
}));

const { startIndexer } = await import("./indexer.js");

beforeEach(() => {
  mockGetBlockNumber.mockReset().mockResolvedValue(100n);
  mockGetLogs.mockReset();
  mockStateFindUnique.mockReset().mockResolvedValue({ id: 1, lastProcessedBlock: 99n });
  mockStateUpsert.mockReset().mockResolvedValue({ id: 1, lastProcessedBlock: 100n });
  mockOrderUpsert.mockReset();
  mockOrderUpdate.mockReset();
});

afterEach(() => {
  vi.clearAllTimers();
});

describe("startIndexer", () => {
  test("does not advance the checkpoint when applying an event fails", async () => {
    const databaseError = new Error("database unavailable");
    mockGetLogs.mockResolvedValue([
      {
        eventName: "OrderExecuted",
        blockNumber: 100n,
        transactionHash: `0x${"1".repeat(64)}`,
        logIndex: 0,
        args: { orderId: 1n, executor: `0x${"2".repeat(40)}`, executionPrice: 1n, keeperFee: 1n, amountOut: 1n },
      },
    ]);
    mockOrderUpdate.mockRejectedValue(databaseError);

    await expect(startIndexer(`0x${"3".repeat(40)}`, 50n)).rejects.toBe(databaseError);

    expect(mockStateUpsert).not.toHaveBeenCalled();
  });

  test("backfills from the deployment block when no checkpoint exists", async () => {
    mockStateFindUnique.mockResolvedValueOnce(null);
    mockGetLogs.mockResolvedValue([]);

    await startIndexer(`0x${"3".repeat(40)}`, 75n);

    expect(mockGetLogs).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ fromBlock: 75n, toBlock: 84n }),
    );
    expect(mockStateUpsert).toHaveBeenLastCalledWith({
      where: { id: 1 },
      create: { id: 1, lastProcessedBlock: 100n },
      update: { lastProcessedBlock: 100n },
    });
  });

  test("rejects an expiry outside the JavaScript Date range without advancing", async () => {
    mockGetLogs.mockResolvedValue([
      {
        eventName: "OrderCreated",
        blockNumber: 100n,
        transactionHash: `0x${"1".repeat(64)}`,
        logIndex: 0,
        args: {
          orderId: 1n,
          owner: `0x${"2".repeat(40)}`,
          side: 0,
          condition: 0,
          targetPrice: 1n,
          amount: 1n,
          maxSlippageBps: 100n,
          expiry: 8_640_000_000_001n,
        },
      },
    ]);

    await expect(startIndexer(`0x${"3".repeat(40)}`, 50n)).rejects.toThrow(
      "expiry 8640000000001 is outside the JavaScript Date range",
    );
    expect(mockOrderUpsert).not.toHaveBeenCalled();
    expect(mockStateUpsert).not.toHaveBeenCalled();
  });

  test("rejects an order id outside the PostgreSQL integer range without advancing", async () => {
    mockGetLogs.mockResolvedValue([
      {
        eventName: "OrderCancelled",
        blockNumber: 100n,
        transactionHash: `0x${"1".repeat(64)}`,
        logIndex: 0,
        args: { orderId: 2_147_483_648n, owner: `0x${"2".repeat(40)}`, refundAmount: 1n },
      },
    ]);

    await expect(startIndexer(`0x${"3".repeat(40)}`, 50n)).rejects.toThrow(
      "orderId 2147483648 exceeds the OrderKeeper MVP indexer's maximum supported value",
    );
    expect(mockOrderUpdate).not.toHaveBeenCalled();
    expect(mockStateUpsert).not.toHaveBeenCalled();
  });
});
