import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

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

    await expect(startIndexer(`0x${"3".repeat(40)}`)).rejects.toBe(databaseError);

    expect(mockStateUpsert).not.toHaveBeenCalled();
  });
});
