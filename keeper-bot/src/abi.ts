// Hand-written fragments, not generated from contracts/'s build output —
// keeper-bot is an independent service (per CLAUDE.md's Planned Structure:
// "no shared monorepo tooling... prefer duplication over premature
// abstraction"). Keep in sync with contracts/src/OrderKeeper.sol if it
// changes. Errors are included so viem can decode revert reasons.
export const orderKeeperAbi = [
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
] as const;
