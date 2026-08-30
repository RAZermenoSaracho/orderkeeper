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

## [OPEN] Link Module 13 RWAAssetToken reference once published

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

## [RECURRING — NOT A ONE-TIME BUG] Sepolia WETH/quoteToken pool drifts from live oracle price

- **Component**: contracts
- **Discovered**: 2026-08-17 — while adding `test_Fork_ExecuteOrder_RealSwap`
  to `contracts/test/OrderKeeper.fork.t.sol`
- **First resolved**: 2026-08-29 — resolved incidentally by the 2026-08-26
  redeploy; confirmed by measuring both pools directly
- **Recurred**: 2026-08-30 — a *different* pool (Milestone 15's
  2026-08-29 redeploy), already drifted again by the time it was
  re-measured, confirming this is a standing characteristic of an
  unarbitraged testnet pool rather than a bug that gets fixed once
- **Status**: recurring / known limitation — see README.md's "Accepted
  MVP slippage tolerance limitation" for the standing explanation; this
  entry is now the incident log, not the authoritative current guidance

**Original problem**: the WETH/DemoUSDC Uniswap V2 pool was seeded at
ETH ≈ $1,900 and never arbitraged since — no bots trade this testnet
pool. With the oracle at ETH ≈ $2,500 that was a ~24% gap, so a realistic
`maxSlippageBps` (e.g. 1%) correctly reverted with
`UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT` — slippage protection
working as designed, but leaving the pool unusable for a convincing live
demo without either re-seeding liquidity or accepting an unrealistically
wide tolerance.

**Resolution**: the 2026-08-26 redeploy deployed a *new* DemoUSDC
(`0xDB7B8e1c…`) and seeded a fresh WETH/DemoUSDC pool
(`0x38BDAA4c…`) at the then-current price, which incidentally fixed this.
Measured 2026-08-29 against the live factory:

| Pool | Reserves | Implied ETH | vs oracle ($2,450.63) |
|---|---|---|---|
| Current (`0x38BDAA4c…`, new DemoUSDC) | 1.0030 WETH / 2,492.62 mUSDC | $2,485.20 | **+1.41%** |
| Old (`0xCC492865…`, pre-redeploy DemoUSDC) | 1.0010 WETH / 1,902.42 mUSDC | $1,900.50 | −22.4% |

So the ~24% figure describes the *old* pool, which the current deployment
no longer uses. A realistic 2–3% `maxSlippageBps` now works against the
live pool — no re-seeding needed before Module 16, and the demo can use a
credible tolerance rather than an inflated one.

`contracts/test/OrderKeeper.fork.t.sol` was still pinned to the old
DemoUSDC (and so still needed 30% slippage); it now points at the current
one and passes at 5%, with the remaining headroom covering the 0.3% swap
fee and price impact against a ~1 WETH pool rather than a broken price.

Two caveats worth keeping in mind:

- The current pool is small (~1 WETH), so price impact grows quickly with
  order size. Demo-sized orders (≤ 0.01 ETH) are fine; large ones are not.
- Drift will re-accumulate over time for exactly the original reason —
  nothing arbitrages this pool. If fork tests start failing at 5%, check
  the pool against the oracle before widening tolerance: a growing gap is
  the signal, and widening would hide it.

**2026-08-30 update — exactly what the second caveat predicted.**
Milestone 15's 2026-08-29 redeploy seeded yet another new pool (new
DemoUSDC `0x84811D4C…`, pool `0x8Bf87713…`). Measured directly the next
day:

| Pool | Reserves | Implied ETH | vs oracle (~$2,506.74) |
|---|---|---|---|
| Current (`0x8Bf87713…`, post-Milestone-15 DemoUSDC) | 0.9728 WETH / 2,522.36 quoteToken | $2,592.96 | **+3.44%** |

Already wider than the +1.41% recorded one day after the *previous*
redeploy, despite this pool also having just been freshly seeded at
deploy-time oracle price — confirming drift accumulates quickly on an
unarbitraged pool this shallow, not just over long idle periods.
Real-swap simulation against these exact reserves (constant-product
formula, not just the naive reserve-ratio percentage above) showed a
small Sell clearing at 1% slippage while a modest Buy needed slippage
above 3% and below 10%, and a Buy roughly 100x larger needed slippage in
the 20%+ range from price impact alone — see README.md's "Accepted MVP
slippage tolerance limitation" for the full traced mechanism and
`contracts/test/OrderKeeper.fork.t.sol`'s current tolerance, which still
passed at 5% for its specific (small) order sizes at measurement time.

The conclusion this entry now supports: don't try to pin a single
"correct" `maxSlippageBps` value for Sepolia testing, and don't treat a
previously-measured low-drift snapshot as durable. Read the live pool
before relying on any specific percentage, exactly as `RUNBOOK.md`'s
end-to-end workflow already instructs.

---

## [RESOLVED] Sepolia DAI feed is registered but intermittently stale

- **Component**: contracts / frontend
- **Discovered**: 2026-08-28 — while verifying Milestone 12's (Multi-Asset
  Selector) newly-registered feeds against the live deployed contract
- **Resolved**: 2026-08-29 — resolved by Milestone 12 being reverted and
  Milestone 15 shipping a clean redeploy, not by fixing the staleness
  itself
- **Status**: resolved (feature that needed it no longer exists)

**Original problem**: DAI's Sepolia Chainlink feed
(`0x14866185B1962B63C3Ea9E03Bc1da838bab34C19`) was correctly registered
via `addPriceFeed()`, but `latestRoundData()`'s `updatedAt` was found
~3.4 hours stale at time of testing, against `OrderKeeper`'s 1-hour
`PRICE_STALENESS_THRESHOLD` — `getAssetPrice()` correctly reverted with
`InvalidPrice()` in that state. This was the staleness guard working as
designed, not a bug — low testnet activity means the feed's own DON
doesn't update it as reliably as a mainnet feed would, and no more
actively-maintained Sepolia DAI feed appears to exist (there's no
canonical DAI issuer on Sepolia to begin with). DAI was removed from
`frontend/src/config.ts`'s `SUPPORTED_ASSETS` for this reason, staying
registered on-chain but not selectable.

**Resolution**: moot rather than fixed. Milestone 12's multi-asset
selector — the only reason DAI's feed was registered at all — was itself
reverted (see `ROADMAP.md`'s Milestone 12 Outcome note): auditing a
genuine multi-asset redesign found no Uniswap V2 pool for LINK on Sepolia
at all, making the selector unbuildable as more than a decorative price
trigger. Milestone 15 replaced it with a clean redeploy of `OrderKeeper`
supporting bidirectional Buy/Sell on the single WETH/quoteToken pair —
the new deploy script (`contracts/script/DeployOrderKeeper.s.sol`)
registers only WETH's feed, so the current live contract has no DAI feed
registered at all, and `RUNBOOK.md`'s "Register additional price feeds"
workflow (which this DAI entry referenced) was removed entirely, not just
edited. Nothing left to track here.

---
