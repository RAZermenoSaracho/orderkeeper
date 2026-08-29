// Hand-written event fragments, not generated from contracts/'s build
// output — order-indexer is an independent service (per CLAUDE.md's
// Planned Structure: "no shared monorepo tooling... prefer duplication
// over premature abstraction"), so it doesn't depend on contracts/ having
// been built. Keep these in sync with the event declarations in
// contracts/src/OrderKeeper.sol if that contract ever changes.
export const orderKeeperEventsAbi = [
  {
    type: "event",
    name: "OrderCreated",
    inputs: [
      { name: "orderId", type: "uint256", indexed: true },
      { name: "owner", type: "address", indexed: true },
      // `side` replaced the old `asset` field: orders now trade one fixed
      // pair in either direction, rather than naming an asset that was only
      // ever a price trigger. 0 = Sell (deposits ETH), 1 = Buy (deposits
      // quoteToken).
      { name: "side", type: "uint8", indexed: false },
      { name: "condition", type: "uint8", indexed: false },
      { name: "targetPrice", type: "uint256", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
      { name: "maxSlippageBps", type: "uint256", indexed: false },
      { name: "expiry", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "OrderExecuted",
    inputs: [
      { name: "orderId", type: "uint256", indexed: true },
      { name: "executor", type: "address", indexed: true },
      { name: "executionPrice", type: "uint256", indexed: false },
      { name: "keeperFee", type: "uint256", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "OrderCancelled",
    inputs: [
      { name: "orderId", type: "uint256", indexed: true },
      { name: "owner", type: "address", indexed: true },
      { name: "refundAmount", type: "uint256", indexed: false },
    ],
  },
] as const;
