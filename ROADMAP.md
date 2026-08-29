# Roadmap

## Product Vision

OrderKeeper is a trust-minimized limit-order keeper bot for EVM chains: I deposit
funds and define a price condition, an off-chain keeper bot monitors a
Chainlink price feed and triggers execution via Uniswap, and the contract
independently re-verifies that price on-chain before any funds move — the
keeper bot is trusted only as a trigger, never as a price source. Past the
bootcamp MVP, my direction is to round out the fixed-pair Buy/Sell product
surface, harden the three off-chain services with
real test coverage to match `contracts/`'s existing bar, and keep the
whole stack demo-ready and verifiably trust-minimized end-to-end.

## Current Architecture

- **`contracts/`** — Foundry, OpenZeppelin (`IERC20`, `ReentrancyGuard`),
  Chainlink `AggregatorV3Interface`, Uniswap V2 router interface
- **`order-indexer/`** — Node.js, TypeScript, Fastify, viem, PostgreSQL +
  Prisma
- **`keeper-bot/`** — Node.js, TypeScript, viem
- **`frontend/`** — React, Vite, TypeScript, wagmi, viem

## Current Product Capabilities

**Order Lifecycle**
- Create, cancel, and execute orders in either direction — Sell (deposit
  ETH, sell when ETH rises to target) or Buy (deposit quoteToken, buy ETH
  when ETH falls to target) — on the single WETH/quoteToken pair, with
  checks-effects-interactions and `ReentrancyGuard` on every fund-moving
  path
- Pull-over-push refunds (ETH for Sell, quoteToken for Buy) and keeper fee
  payout, denominated in whatever the order deposited

**Price Verification & Execution Safety**
- Price condition re-verified on-chain against Chainlink inside
  `executeOrder()` — the keeper bot is never trusted as a price source
- Slippage protection (`maxSlippageBps`) confirmed working under a real
  revert during live testing, not just in unit tests

**Indexing & Monitoring**
- Indexes `OrderCreated` / `OrderExecuted` / `OrderCancelled` into
  PostgreSQL via Prisma
- Read-only, CORS-enabled REST API (`GET /orders`, optional `?status=` and
  `?owner=` filters) — no private key held
- Chunked `eth_getLogs` backfill with exponential 429 backoff and a
  proactive inter-chunk throttle
- Live event watching via direct `eth_getLogs` polling, not viem's
  filter-based `watchContractEvent` (unreliable against Alchemy's free
  tier)

**Frontend**
- Wallet connect via wagmi's injected connector
- Order creation form with a Buy/Sell toggle, condition, USD target price,
  a deposit field denominated per side (ETH for Sell, quoteToken for
  Buy), slippage, and expiry — plus the ERC20 `approve()` step Buy orders
  need before `createOrder()`. No per-order asset selector: both sides
  trade the one WETH/quoteToken pair (see Milestone 12's revert)
- Order list scoped to the connected wallet, sorted newest-first, with
  live status and a Sepolia Etherscan link on executed orders
- Cancellation for pending orders

**Testing & Deployment**
- 100% test coverage on `contracts/` (76 local tests, plus the fork suite)
  across unit, fork, fuzz, and invariant categories
- Slither-clean `src/` — every finding triaged, fixed or
  documented-suppressed
- Deployed and verified on Sepolia Etherscan: OrderKeeper
  `0x907dC6392df5973aD82816C05E2e15F821054503`, DemoUSDC
  `0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929`

---

## Current Development Focus

**Status: ACTIVE**

With Milestone 15 (bidirectional Buy/Sell orders) confirmed and shipped —
verified live on Sepolia in both directions, including a real bug found
and fixed mid-verification (see Milestone 15's Outcome note) — the
product now supports genuine two-directional trading of the WETH/
quoteToken pair, not just a one-way sell flow with a decorative asset
selector. My focus shifts to Milestone 14, continuous deployment to a
real production server: this one involves several real architectural
decisions (pm2 process definitions, how GitHub Actions authenticates
to/triggers the server, push vs. pull deploy, server-side secrets
handling) I still need to make before implementation starts, per
CLAUDE.md's Architectural Decision Documentation rule.

# Milestone 1 - Contracts (Order Lifecycle + Oracle Verification)

Status: COMPLETED

Goals:
- Implement `createOrder()` / `executeOrder()` / `cancelOrder()` with
  checks-effects-interactions and `ReentrancyGuard`
- Verify price on-chain against Chainlink at execution time
- Reach 100% test coverage (unit, fork, fuzz, invariant)
- Reach a Slither-clean state on `src/`
- Deploy and verify on Sepolia Etherscan

# Milestone 2 - Order Indexer

Status: COMPLETED

Goals:
- Index `OrderCreated` / `OrderExecuted` / `OrderCancelled` into
  PostgreSQL via Prisma
- Expose a read-only, CORS-enabled `GET /orders` REST API
- Chunk `eth_getLogs` backfill with 429 backoff and inter-chunk throttling
- Replace filter-based `watchContractEvent` with direct `eth_getLogs`
  polling for live events

# Milestone 3 - Keeper Bot

Status: COMPLETED

Goals:
- Poll `order-indexer` for pending orders
- Re-verify each order's price condition via `checkPriceCondition()`
  before calling `executeOrder()`
- Hold an operator private key separate from user funds and the
  `contracts/` deployer key

# Milestone 4 - Frontend MVP (Connect, Create, List, Cancel)

Status: COMPLETED
Depends on: Milestone 1, Milestone 2

Goals:
- Wallet connect via wagmi's injected connector
- Order creation form (asset, condition, target price, deposit, slippage,
  expiry)
- Order list scoped to the connected wallet
- Cancellation for pending orders

# Milestone 5 - Verified End-to-End Run

Status: COMPLETED
Depends on: Milestone 1, Milestone 2, Milestone 3, Milestone 4

Goals:
- Confirm the full stack live on Sepolia: frontend creation →
  `order-indexer` capture → `keeper-bot` execution → frontend status
  update
- Exercise the slippage guard for real: a 100 bps order reverted with
  `INSUFFICIENT_OUTPUT_AMOUNT`, a 3000 bps order executed successfully

# Milestone 6 - Rate Limiting on Order-Indexer's Public API

Status: COMPLETED
Depends on: Milestone 2

Goals:
- Add `@fastify/rate-limit` (or equivalent) to `order-indexer`'s
  `GET /orders` endpoint
- Prevent abuse/DoS on a service that has no auth and is intended to run
  publicly

# Milestone 7 - CI Pipeline

Status: COMPLETED
Depends on: Milestone 1

Goals:
- Add a GitHub Actions workflow running `forge test`, `forge coverage`,
  and `slither` on every push/PR
- Add lint checks for `order-indexer` / `keeper-bot` / `frontend` to the
  same workflow
- Closes the gap between `ci` already being a defined type in CLAUDE.md's
  Commit Convention and no workflow actually existing yet

# Milestone 8 - Solidity Dependency Lockfile for contracts/lib/

Status: COMPLETED
Depends on: Milestone 1

Goals:
- `contracts/lib/` is currently gitignored with no submodules and no
  lockfile — dependencies are installed ad hoc and pinned only via manual
  commands in CI/RUNBOOK.md, not a real lockfile
- v2-periphery specifically cannot be pinned to a tag: the local install
  came from a branch HEAD (reports version `1.1.0-beta.0` in its
  `package.json`), but the only real upstream tag is `v1.0.0-beta.0` — no
  matching tag exists. CI currently installs it from the default branch
  as an approximation, not a guaranteed-reproducible pin (discovered
  during Milestone 7's CI setup)
- Adopt a proper dependency management approach — git submodules,
  Foundry's `soldeer`, or equivalent — so all of `contracts/lib/`,
  including v2-periphery, is exactly reproducible across machines and CI

# Milestone 9 - Mobile-Responsive Layout + Component Reorganization

Status: COMPLETED
Depends on: Milestone 4

Goals:
- Add responsive CSS to `frontend/src/index.css` (existing plain-CSS
  approach, no framework)
- Move loose component files (`App.tsx`, `CreateOrderForm.tsx`,
  `OrderList.tsx`) into `frontend/src/components/`

# Milestone 10 - Multiple Competing Keeper Bots

Status: COMPLETED
Depends on: Milestone 3

Goals:
- Run a second `keeper-bot` instance in parallel against the same
  deployment, with its own operator key
- Confirm the existing race-condition handling (visible in logs as
  "expected race, retrying next cycle") holds up under real concurrent
  competition, not just one bot's own retry logic
- Validates the "permissionless execution" premise — that anyone can run
  a keeper-bot and compete for the fee — which has so far only ever been
  tested with a single instance

# Milestone 11 - Live Price Display

Status: COMPLETED
Depends on: Milestone 4

Goals:
- Poll the contract's own `getAssetPrice()` for the selected asset every
  ~15s via `eth_call`; show a "Last updated Xs ago" label
- Chosen over reading Chainlink's `AggregatorV3Interface` directly:
  `getAssetPrice()` is exactly what `executeOrder()` evaluates (staleness
  checks and decimal normalization included), so the display can never
  disagree with what the contract would actually enforce
- Tradeoff to track: one additional `eth_call` every ~15s per selected
  asset, on top of `order-indexer`'s and `keeper-bot`'s own polling —
  this session already hit Alchemy's free-tier rate limit once during
  `order-indexer` backfill, so multiple open tabs may need their own
  backoff

# Milestone 12 - Multi-Asset Selector

Status: COMPLETED, then SUPERSEDED (reverted 2026-08-29)
Depends on: Milestone 4

Goals:
- Register additional Sepolia Chainlink feeds via `addPriceFeed()` and
  add a dropdown to `CreateOrderForm`
- Confirmed feasible now — verified by calling `description()` directly
  against Sepolia, not by trusting docs pages or search results (several
  search hits turned out to be mainnet addresses mislabeled as Sepolia):

  | Asset | Feed address | `description()` |
  |---|---|---|
  | ETH | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | `ETH / USD` (already in use) |
  | BTC | `0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43` | `BTC / USD` |
  | LINK | `0xc59E3633BAAC79493d908e63626716e204A45EdF` | `LINK / USD` |
  | USDC | `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E` | `USDC / USD` |
  | DAI | `0x14866185B1962B63C3Ea9E03Bc1da838bab34C19` | `DAI / USD` |

- Not yet confirmed: SOL, AVAX, MATIC/POL, DOGE, UNI, AAVE, USDT, HYPE —
  Chainlink's price feed addresses page loads its catalog client-side per
  network, which wasn't scriptable with the tools used for this research;
  Chainlink's testnet feed set is a small curated subset of majors, so
  some or all of these eight may not exist on Sepolia at all
- Before implementing: re-verify each candidate's `description()`
  directly against Sepolia (`cast call` / `eth_call`), or check the
  network picker at `docs.chain.link/data-feeds/price-feeds/addresses`
  (select Sepolia) by hand

**Outcome**: BTC, LINK, USDC registered and confirmed live in the
frontend dropdown. DAI's feed is registered on-chain too, but turned out
intermittently stale beyond the contract's 1-hour threshold (low Sepolia
testnet activity) — removed from the frontend's selectable list rather
than reverted on-chain. See ISSUES.md's "Sepolia DAI feed is registered
but intermittently stale" entry. The other eight assets from the research
above were re-checked exhaustively and confirmed infeasible — no Sepolia
feed exists for any of them.

**Superseded 2026-08-29** — the frontend selector was reverted to
WETH-only. Kept in this roadmap rather than deleted: the work shipped and
the feed research below is real and still accurate.

Why it was reverted: the selector was a trigger-only gimmick. Picking BTC
or LINK only chose which Chainlink feed the price condition read — the
contract always swapped WETH for quoteToken regardless, so a user
selecting "LINK" was never able to trade LINK. Auditing the redesign that
would have made it genuine surfaced the harder blocker: **LINK has no
Uniswap V2 pool on Sepolia at all** (verified against the factory at
`0xAC40888A…` — neither LINK/WETH nor LINK/quoteToken exists), and the
WBTC pool that does exist is mispriced ~47% against the BTC/USD oracle.
So the multi-asset story could not have been made real on this testnet
without seeding pools first.

The simpler and more honest product — and the one that ships today — is
bidirectional trading of the single pair that has real liquidity: buy and
sell ETH against quoteToken. That became Milestone 15.

The feed addresses in the table above remain valid and are worth keeping
for any future multi-asset work; what was missing was never the feeds, it
was the pools.

# Milestone 13 - Full Test Coverage (frontend / order-indexer / keeper-bot)

Status: COMPLETED

Goals:
- Adopt Vitest across `frontend/`, `order-indexer/`, and `keeper-bot/` —
  one unified toolchain rather than splitting `node:test` and Vitest
  across the repo
- `frontend/`: Vitest + React Testing Library
- Migrate the existing `order-indexer` test file
  (`orders.test.ts`, currently `node:test`) onto Vitest for consistency
- Priority coverage: `order-indexer`'s `serializeOrder()` (where a real
  Decimal-formatting bug already slipped through), `keeper-bot`'s
  poll/check/execute loop against a mocked `order-indexer` and contract,
  frontend's order creation/cancellation flows against a mocked wagmi
  config
- `contracts/` is already at 100% coverage — no work needed there
- Resolves `.claude/rules/testing.md`'s current note that no testing
  stack has been chosen for these three services

**Outcome**: 60 tests total, all passing — `order-indexer` 17
(`serializeOrder()` plus the full Fastify route layer via `.inject()`:
400 validation, rate limiting, CORS), `keeper-bot` 17 (the poll/check/
execute loop and race-condition handling, plus `indexerClient.ts`'s
fetch/timeout/error logic), `frontend` 26 (`App`, `CreateOrderForm`,
`OrderList`). Coverage on every priority-named file: `order-indexer`'s
`routes/orders.ts` and new `app.ts` 100%, `keeper-bot`'s `keeper.ts` 96%
and `indexerClient.ts` 100%, frontend's `App.tsx` 100%, `CreateOrderForm.tsx`
85%, `OrderList.tsx` 96%. Testing conventions documented in each service's
own `CLAUDE.md` (`order-indexer/CLAUDE.md` and `keeper-bot/CLAUDE.md` are
new; `frontend/CLAUDE.md` gained a Testing section) and in
`.claude/rules/testing.md`. `order-indexer/src/index.ts` was refactored
to extract `app.ts`'s `buildApp()`, split out from the process-starting
`main()`, so the real route/plugin stack is testable via `.inject()`
without a real port — verified against the real running server that the
refactor didn't change production behavior. `.github/workflows/ci.yml`'s
`keeper-bot` and `frontend` jobs were missing a `Test` step entirely
(built before either service had tests) — added, matching
`order-indexer`'s existing pattern.

# Milestone 14 - Continuous Deployment to Production Server

Status: PLANNED

Goals:
- Deploy the full stack (frontend, order-indexer, keeper-bot) to
  Ricardo's Mac server, exposed via Cloudflare Tunnel, process-managed
  with pm2
- Add a GitHub Actions workflow that redeploys automatically whenever
  changes are pushed/merged to main
- This needs real architectural decisions — pm2 process definitions, how
  the GitHub Actions workflow authenticates to/triggers the server,
  push-to-deploy via SSH vs. pull-based, env/secrets handling on the
  server — per CLAUDE.md's Architectural Decision Documentation rule,
  ask before implementing rather than guessing

# Milestone 15 - Bidirectional Limit Orders (Buy + Sell)

Status: COMPLETED

Goals:
- Scope is deliberately the single existing pair (WETH ↔ quoteToken)
  traded in both directions — not arbitrary token pairs. Sell keeps the
  existing behaviour (deposit ETH, sell when ETH rises to target); Buy is
  new (deposit quoteToken, buy ETH when ETH falls to target)
- `Order` struct: add a `side` field (`Buy`/`Sell` enum). No
  `conditionToken` field is needed — the condition always gates on ETH's
  price via the existing `getAssetPrice(weth)`, regardless of side. The
  former `asset` field goes away with the multi-asset selector (see
  Milestone 12): it was only ever a price trigger
- `createOrder()`: branch on side — Sell keeps the `msg.value` flow, Buy
  pulls a quoteToken deposit via `safeTransferFrom` (needs `SafeERC20`).
  `nonReentrant` becomes mandatory here: the function's existing NatSpec
  justifies skipping it on "no external call", which `transferFrom`
  breaks
- `executeOrder()`: branch swap direction (`swapExactETHForTokens` for
  Sell, `swapExactTokensForETH` for Buy). Keeper fee stays denominated in
  whatever the order deposited, so it never needs its own swap
- `cancelOrder()`: ERC20 refund branch alongside the existing ETH refund
- `_minAmountOut()`: handle both directions off the same oracle price —
  Sell multiplies by the ETH price, Buy divides by it; the conversion
  just flips
- Solvency invariant: track ETH and quoteToken balances separately rather
  than a single scalar, so a bug in one asset's accounting can't be
  masked by the other
- Routing unchanged: the same fixed pair, reversed for Buy
- Test suite: unit/fork/fuzz/invariant all updated. The mock router must
  actually `transferFrom` ERC20 input on the quoteToken→WETH direction,
  not just mint output — a mock that only minted would leave the
  contract's quoteToken balance untouched and the invariant would pass
  while proving nothing

**Outcome**: implemented exactly as scoped above and verified live on
Sepolia, both directions. Redeployed (clean redeploy, no migration —
`Order.asset` removed entirely, replaced by `side`):

- **OrderKeeper**: [`0x907dC6392df5973aD82816C05E2e15F821054503`](https://sepolia.etherscan.io/address/0x907dC6392df5973aD82816C05E2e15F821054503) — verified on Sepolia Etherscan
- **DemoUSDC**: [`0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929`](https://sepolia.etherscan.io/address/0x84811D4CBE30fA5Dd42a7421D771C3fA1cD31929) — verified on Sepolia Etherscan

Live verification, three orders against the new deployment (full tx
hashes and figures in README.md's On-Chain Activity section):

- **Order #0 (Sell)**: 0.001 ETH deposited, executed successfully —
  `GreaterOrEqual` condition on ETH price, keeper fee paid in ETH,
  DemoUSDC paid out to the owner.
- **Order #1 (Buy)**: created and executed against a disposable test
  wallet while diagnosing a bug found during this verification (below) —
  confirmed the fix before re-testing through the real frontend.
- **Order #2 (Buy)**: created through the actual frontend UI with
  Ricardo's own wallet, post-fix — `LessOrEqual` condition, quoteToken
  deposited, keeper fee paid in quoteToken, ETH paid out to the owner.
  Execution landed 4 blocks after creation (vs. 1–2 for the other two
  orders) — `keeper-bot` correctly retried across poll cycles rather than
  submitting once and giving up, the race/retry handling this milestone's
  Goals called for (`EXPECTED_RACE_ERRORS` in `keeper-bot/src/keeper.ts`)
  holding up under real conditions, not just the unit tests.

**Bug found and fixed during this verification**: `frontend/src/config.ts`'s
`quoteToken.address` was stale, still pointing at a DemoUSDC deployment
from *before* this milestone's redeploy. Both the old and new DemoUSDC
happen to share the symbol `mUSDC` and 6 decimals, so nothing about the
mismatch was visible in the UI. Effect: the frontend's `approve()` call
succeeded — just against the wrong contract — so when `createOrder()` ran
on the real OrderKeeper, its `safeTransferFrom` found zero allowance and
reverted. A reverted transaction emits no events, so `order-indexer`
correctly showed nothing, which is exactly what made this tricky to
diagnose from the indexer alone rather than the chain directly. Root-
caused by cross-checking every address `config.ts` and `RUNBOOK.md`
referenced against the live contract's own `quoteToken()`/`weth()` return
values (`cast call`), not assumed from `deployments/sepolia.json` alone.
Fixed in both files; `config.ts` now carries a comment explaining why this
class of bug recurs on every redeploy (DemoUSDC has no canonical fixed
address) and what to check.

# Milestone 16 - Chainlink Automation as Alternative Trigger Source

Status: PLANNED
Depends on: Milestone 1, Milestone 3

Goals:
- Implement Chainlink Automation (`checkUpkeep()` / `performUpkeep()`) as
  an alternative to the self-run `keeper-bot`
- Register and run a real Automation upkeep against the deployed contract
- Compare in practice against the self-run `keeper-bot`: the uptime vs.
  transparency tradeoff already documented in CLAUDE.md/README.md's
  Design Decisions, but never tested concretely
- This is the "reversible decision" CLAUDE.md/README.md already flag —
  implementing it doesn't require redesigning `executeOrder()`'s
  verification logic

# Milestone 17 - Operational Monitoring/Alerting

Status: PLANNED
Depends on: Milestone 2, Milestone 3

Goals:
- Add uptime/health monitoring for `order-indexer` and `keeper-bot` in a
  persistent (non-local) deployment
- Add alerting on downtime (e.g. missed poll cycles, failed RPC/DB
  connections)
- Optional hardening — relevant once either service runs somewhere
  long-lived, not required for the Sepolia MVP demo

# Milestone 18 - Partial Order Fills / Additional Condition Types

Status: PLANNED
Depends on: Milestone 1

Goals:
- Support partial fills of an order's deposited amount, rather than
  all-or-nothing execution
- Add condition types beyond `GreaterOrEqual` / `LessOrEqual` (e.g. range
  conditions)
- Requires reworking the solvency invariant (contract balance == sum of
  active order amounts) and its fuzz/invariant tests accordingly
- Optional product expansion — not required for MVP

# Milestone 19 - Mainnet or L2 Deployment

Status: PLANNED
Depends on: Milestone 1

Goals:
- Deploy to mainnet or an L2 (Arbitrum, Base, or Optimism)
- Real fix for the testnet pool/oracle drift issue documented in
  ISSUES.md — real DEX pools stay arbitrage-aligned, unlike an
  unarbitraged testnet pool
- Ties into README.md's "real income potential" framing — a live keeper
  fee only means something against real liquidity and real funds

---

# Success Criteria

OrderKeeper's roadmap is fulfilled when:

- Users can place, cancel, and have executed both buy and sell limit
  orders on the ETH/quoteToken pair — a real trade in either direction,
  not a one-way flow
- The frontend shows live, on-chain-sourced pricing context before a user
  commits to a condition
- The UI works cleanly on both desktop and mobile
- `frontend/`, `order-indexer/`, and `keeper-bot/` all have real automated
  test coverage, matching `contracts/`'s existing bar
- The full stack remains verifiably trust-minimized end-to-end: the keeper bot
  only ever triggers, the contract alone decides
