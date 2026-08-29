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
      // 0 = Sell (deposit ETH as msg.value), 1 = Buy (deposit quoteToken,
      // pulled via transferFrom — requires a prior approve()).
      { name: "side", type: "uint8" },
      { name: "condition", type: "uint8" },
      { name: "targetPrice", type: "uint256" },
      { name: "amount", type: "uint256" },
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
    name: "getAssetPrice",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "price", type: "uint256" }],
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
    type: "error",
    name: "InvalidEthValue",
    inputs: [
      { name: "side", type: "uint8" },
      { name: "sent", type: "uint256" },
      { name: "expected", type: "uint256" },
    ],
  },
  {
    type: "event",
    name: "OrderCreated",
    inputs: [
      { name: "orderId", type: "uint256", indexed: true },
      { name: "owner", type: "address", indexed: true },
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

/// Minimal ERC20 surface for the Buy-order approve flow: a Buy order's
/// quoteToken deposit is pulled via transferFrom, so the user must approve
/// OrderKeeper for at least the order amount before createOrder can succeed.
export const erc20Abi = [
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "remaining", type: "uint256" }],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
    ],
    outputs: [{ name: "success", type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "balance", type: "uint256" }],
  },
] as const;
