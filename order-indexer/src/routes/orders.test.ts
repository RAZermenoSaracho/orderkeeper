import { describe, expect, test } from "vitest";
import { Prisma } from "@prisma/client";
import type { Order } from "@prisma/client";
import { serializeOrder } from "./orders.js";

// A full Order fixture with every Decimal/BigInt field large enough to
// trigger Decimal.toString()'s exponential notation (kicks in at 1e21) —
// reproduces the exact shape returned by GET /orders.
function makeOrder(overrides: Partial<Order> = {}): Order {
  return {
    orderId: 0,
    owner: "0x369A2e8133Ea0670fCC7C96ff3220c43D3ffeA7A",
    side: "Sell",
    condition: "GreaterOrEqual",
    targetPrice: new Prisma.Decimal("1000000000000000000000"),
    amount: new Prisma.Decimal("1000000000000000000000"),
    maxSlippageBps: 100,
    expiry: new Date("2026-08-17T18:40:35.000Z"),
    status: "Executed",
    createdAtBlock: 11509603n,
    createdAtTx: "0x71945d01dd3589745bc41113afc325d2b1fa67514379d9a0efa0ba4d52c3b2f7",
    executedAtBlock: 11509604n,
    executedAtTx: "0x3686d6b77f04fb0fa09bf27878753efebe63972b53fb5a1ff81ba08638ae737f",
    executionPrice: new Prisma.Decimal("1907173604190000000000"),
    keeperFee: new Prisma.Decimal("5000000000000"),
    amountOut: new Prisma.Decimal("1887231"),
    cancelledAtBlock: null,
    cancelledAtTx: null,
    indexedAt: new Date("2026-08-17T18:40:40.000Z"),
    updatedAt: new Date("2026-08-17T18:40:40.000Z"),
    ...overrides,
  };
}

describe("serializeOrder", () => {
  test("outputs plain integer strings, not exponential notation, for large Decimal fields", () => {
    const serialized = serializeOrder(makeOrder());

    expect(serialized.targetPrice).toBe("1000000000000000000000");
    expect(serialized.executionPrice).toBe("1907173604190000000000");

    // Regression guard: these are the exact values that previously
    // serialized as "1e+21" / "1.90717360419e+21" via Decimal.toString(),
    // which BigInt() cannot parse.
    expect(serialized.targetPrice).not.toMatch(/e\+/);
    expect(serialized.executionPrice).not.toMatch(/e\+/);
    expect(() => BigInt(serialized.targetPrice)).not.toThrow();
    expect(() => BigInt(serialized.executionPrice as string)).not.toThrow();
  });

  test("outputs plain integer strings for amount and keeperFee at ordinary (non-exponential) magnitudes", () => {
    const serialized = serializeOrder(makeOrder());

    expect(serialized.amount).toBe("1000000000000000000000");
    expect(serialized.keeperFee).toBe("5000000000000");
    expect(() => BigInt(serialized.amount)).not.toThrow();
    expect(() => BigInt(serialized.keeperFee as string)).not.toThrow();
  });

  test("outputs a plain integer string for amountOut", () => {
    const serialized = serializeOrder(makeOrder());

    expect(serialized.amountOut).toBe("1887231");
    expect(() => BigInt(serialized.amountOut as string)).not.toThrow();
  });

  test("passes through null for unset executed-only Decimal fields on a pending order", () => {
    const serialized = serializeOrder(
      makeOrder({
        status: "Pending",
        executedAtBlock: null,
        executedAtTx: null,
        executionPrice: null,
        keeperFee: null,
        amountOut: null,
      }),
    );

    expect(serialized.executionPrice).toBeNull();
    expect(serialized.keeperFee).toBeNull();
    expect(serialized.amountOut).toBeNull();
  });

  test("serializes orderId, owner, side, condition, maxSlippageBps, and status verbatim", () => {
    const serialized = serializeOrder(makeOrder());

    expect(serialized.orderId).toBe(0);
    expect(serialized.owner).toBe("0x369A2e8133Ea0670fCC7C96ff3220c43D3ffeA7A");
    expect(serialized.side).toBe("Sell");
    expect(serialized.condition).toBe("GreaterOrEqual");
    expect(serialized.maxSlippageBps).toBe(100);
    expect(serialized.status).toBe("Executed");
  });

  test("serializes a Buy order's side", () => {
    const serialized = serializeOrder(makeOrder({ side: "Buy" }));

    expect(serialized.side).toBe("Buy");
  });

  test("serializes block numbers as strings and expiry as an ISO 8601 string", () => {
    const serialized = serializeOrder(makeOrder());

    expect(serialized.createdAtBlock).toBe("11509603");
    expect(serialized.executedAtBlock).toBe("11509604");
    expect(serialized.expiry).toBe("2026-08-17T18:40:35.000Z");
  });

  test("passes through null for cancelledAtBlock/cancelledAtTx on a non-cancelled order", () => {
    const serialized = serializeOrder(makeOrder());

    expect(serialized.cancelledAtBlock).toBeNull();
    expect(serialized.cancelledAtTx).toBeNull();
  });

  test("serializes cancelledAtBlock/cancelledAtTx for a cancelled order", () => {
    const serialized = serializeOrder(
      makeOrder({
        status: "Cancelled",
        cancelledAtBlock: 11509700n,
        cancelledAtTx: "0xaaaa1111dd3589745bc41113afc325d2b1fa67514379d9a0efa0ba4d52c3b2f7",
      }),
    );

    expect(serialized.status).toBe("Cancelled");
    expect(serialized.cancelledAtBlock).toBe("11509700");
    expect(serialized.cancelledAtTx).toBe("0xaaaa1111dd3589745bc41113afc325d2b1fa67514379d9a0efa0ba4d52c3b2f7");
  });
});
