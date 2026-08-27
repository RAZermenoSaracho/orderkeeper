// Hand-copied from keeper-bot/src/abi.ts (functions/errors) and
// order-indexer/src/abi.ts (events) rather than regenerated, per those
// files' own rationale: no shared monorepo tooling between services (see
// CLAUDE.md's Planned Structure), so duplication is preferred over a
// premature shared-types package. Keep in sync with
// contracts/src/OrderKeeper.sol if it changes.
export const orderKeeperAbi = [
  {
    type: "function",
    name: "createOrder",
    stateMutability: "payable",
    inputs: [
      { name: "asset", type: "address" },
      { name: "condition", type: "uint8" },
      { name: "targetPrice", type: "uint256" },
      { name: "maxSlippageBps", type: "uint256" },
      { name: "expiry", type: "uint256" },
    ],
    outputs: [{ name: "orderId", type: "uint256" }],
  },
  {
    type: "function",
    name: "cancelOrder",
    stateMutability: "nonpayable",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "checkPriceCondition",
    stateMutability: "view",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [{ name: "met", type: "bool" }],
  },
  {
    type: "function",
    name: "executeOrder",
    stateMutability: "nonpayable",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  { type: "error", name: "OrderNotFound", inputs: [{ name: "orderId", type: "uint256" }] },
  {
    type: "error",
    name: "OrderNotPending",
    inputs: [
      { name: "orderId", type: "uint256" },
      { name: "status", type: "uint8" },
    ],
  },
  {
    type: "error",
    name: "OrderExpired",
    inputs: [
      { name: "orderId", type: "uint256" },
      { name: "expiry", type: "uint256" },
    ],
  },
  { type: "error", name: "ConditionNotMet", inputs: [{ name: "orderId", type: "uint256" }] },
  { type: "error", name: "UnsupportedAsset", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "InvalidPrice", inputs: [] },
  { type: "error", name: "KeeperFeeTransferFailed", inputs: [] },
  { type: "error", name: "ZeroAmount", inputs: [] },
  { type: "error", name: "InvalidExpiry", inputs: [] },
  { type: "error", name: "InvalidSlippage", inputs: [{ name: "maxSlippageBps", type: "uint256" }] },
  {
    type: "error",
    name: "NotOrderOwner",
    inputs: [
      { name: "caller", type: "address" },
      { name: "orderId", type: "uint256" },
    ],
  },
  { type: "error", name: "RefundFailed", inputs: [] },
  {
    type: "event",
    name: "OrderCreated",
    inputs: [
      { name: "orderId", type: "uint256", indexed: true },
      { name: "owner", type: "address", indexed: true },
      { name: "asset", type: "address", indexed: true },
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
