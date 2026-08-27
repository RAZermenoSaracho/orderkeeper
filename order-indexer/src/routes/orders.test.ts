import { test } from "node:test";
import assert from "node:assert/strict";
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
    asset: "0x1287B650e882514447b96a49a0f8DC1040B26d2A",
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

test("serializeOrder outputs plain integer strings, not exponential notation, for large Decimal fields", () => {
  const serialized = serializeOrder(makeOrder());

  assert.equal(serialized.targetPrice, "1000000000000000000000");
  assert.equal(serialized.executionPrice, "1907173604190000000000");

  // Regression guard: these are the exact values that previously
  // serialized as "1e+21" / "1.90717360419e+21" via Decimal.toString(),
  // which BigInt() cannot parse.
  assert.doesNotMatch(serialized.targetPrice, /e\+/);
  assert.doesNotMatch(serialized.executionPrice, /e\+/);
  assert.doesNotThrow(() => BigInt(serialized.targetPrice));
  assert.doesNotThrow(() => BigInt(serialized.executionPrice as string));
});

test("serializeOrder outputs plain integer strings for amount and keeperFee at ordinary (non-exponential) magnitudes", () => {
  const serialized = serializeOrder(makeOrder());

  assert.equal(serialized.amount, "1000000000000000000000");
  assert.equal(serialized.keeperFee, "5000000000000");
  assert.doesNotThrow(() => BigInt(serialized.amount));
  assert.doesNotThrow(() => BigInt(serialized.keeperFee as string));
});

test("serializeOrder outputs a plain integer string for amountOut", () => {
  const serialized = serializeOrder(makeOrder());

  assert.equal(serialized.amountOut, "1887231");
  assert.doesNotThrow(() => BigInt(serialized.amountOut as string));
});

test("serializeOrder passes through null for unset executed-only Decimal fields on a pending order", () => {
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

  assert.equal(serialized.executionPrice, null);
  assert.equal(serialized.keeperFee, null);
  assert.equal(serialized.amountOut, null);
});
