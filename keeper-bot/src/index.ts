// Entry point placeholder — no monitoring/execution logic yet.
//
// Planned shape, per README.md's Architecture and Design Decisions:
//   1. Poll the order-indexer REST API (INDEXER_URL) for pending orders.
//   2. Watch the Chainlink feed (CHAINLINK_ETH_USD_FEED) via viem.
//   3. When a pending order's condition is met, call executeOrder() using
//      the operator key (PRIVATE_KEY) — the contract independently
//      re-verifies the price on-chain before moving any funds, so this
//      bot is trusted only as a trigger, never as a price source.

function main(): void {
  console.log("keeper-bot: scaffold only, no logic implemented yet.");
}

main();
