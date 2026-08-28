# Issues

Lightweight backlog for out-of-scope issues, bugs, and side-tasks
discovered mid-task — not worth fixing in the moment, tracked here so
they aren't lost. Entries are appended chronologically and never deleted;
resolving an entry updates its status and heading tag in place rather than
removing it, so this file doubles as a record of what's been handled.

Resolve open entries with the `resolve-issues` skill
(`.claude/skills/resolve-issues/`), or manually — just follow this format
when adding a new entry.

---

### [OPEN] Link Module 13 RWAAssetToken reference once published

- **Component**: docs
- **Discovered**: 2026-08-16 — while drafting the oracle Design Decisions
  section in README.md/CLAUDE.md
- **Status**: open

README.md's "Design Decisions" section and CLAUDE.md's short cross-
reference both cite "the Module 13 RWAAssetToken assignment" by name only,
with no link — that module currently exists only in Metana's private
bootcamp repo, not a public one. Once I publish that module to my own
GitHub, update both references to link directly to the relevant contract
(the price staleness/decimal-normalization logic being reused for
OrderKeeper's oracle verification) so the reasoning cited for the self-run
keeper-bot decision is independently checkable.

---

### [OPEN] Sepolia WETH/DemoUSDC pool has drifted ~24% from live oracle price

- **Component**: contracts
- **Discovered**: 2026-08-17 — while adding `test_Fork_ExecuteOrder_RealSwap`
  to `contracts/test/OrderKeeper.fork.t.sol`
- **Status**: open

The WETH/DemoUSDC Uniswap V2 pool was seeded at ETH ≈ $1,900 and hasn't
been arbitraged since — no bots trade this testnet pool. The live
Chainlink oracle now reads ETH ≈ $2,500, a ~24% gap. A real order with a
realistic `maxSlippageBps` (e.g. 1%) will correctly have its
`executeOrder()` call revert with
`UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT` — the slippage protection
is working as designed, not a bug — but this makes the pool unusable for
a convincing live demo without either re-seeding liquidity (adding more
WETH + oracle-priced DemoUSDC to rebalance the ratio) or accepting an
unrealistically wide `maxSlippageBps` for the demo run. Already
documented as a troubleshooting symptom in `RUNBOOK.md`'s "End-to-end
oracle loop verification" workflow; this entry tracks the underlying fix
(re-seed liquidity) needed before Module 16.

---

### [OPEN] Sepolia DAI feed is registered but intermittently stale

- **Component**: contracts / frontend
- **Discovered**: 2026-08-28 — while verifying Milestone 12's (Multi-Asset
  Selector) newly-registered feeds against the live deployed contract
- **Status**: open

DAI's Sepolia Chainlink feed (`0x14866185B1962B63C3Ea9E03Bc1da838bab34C19`)
is correctly registered via `addPriceFeed()`, but `latestRoundData()`'s
`updatedAt` was found ~3.4 hours stale at time of testing, against
`OrderKeeper`'s 1-hour `PRICE_STALENESS_THRESHOLD` — `getAssetPrice()`
correctly reverts with `InvalidPrice()` in that state. This is the
staleness guard working as designed, not a bug — same class of limitation
as the WETH/DemoUSDC pool drift above: low testnet activity means the
feed's own DON doesn't update it as reliably as a mainnet feed would.
No fix is available short of finding a more actively-maintained Sepolia
DAI feed, and none appears to exist — there's no canonical DAI issuer on
Sepolia to begin with (see `RUNBOOK.md`'s "Register additional price
feeds" workflow, which already notes this address is "a" DAI-like token,
not "the" one). Not something we're going to resolve; documented as a
known limitation. DAI was removed from `frontend/src/config.ts`'s
`SUPPORTED_ASSETS` for this reason — it stays registered on-chain, just
not offered as a selectable option in the MVP demo.

---
