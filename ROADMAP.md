# Roadmap

## Product Vision

OrderKeeper is a trustless limit-order keeper bot for EVM chains: I deposit
funds and define a price condition, an off-chain keeper bot monitors a
Chainlink price feed and triggers execution via Uniswap, and the contract
independently re-verifies that price on-chain before any funds move — the
keeper bot is trusted only as a trigger, never as a price source. Past the
bootcamp MVP, my direction is to round out the product surface the
contract already supports but the frontend doesn't yet expose (multiple
assets, live pricing context), harden the three off-chain services with
real test coverage to match `contracts/`'s existing bar, and keep the
whole stack demo-ready and verifiably trustless end-to-end.

## Current Architecture

- **`contracts/`** — Foundry, OpenZeppelin (`IERC20`, `ReentrancyGuard`),
  Chainlink `AggregatorV3Interface`, Uniswap V2 router interface
- **`order-indexer/`** — Node.js, TypeScript, Fastify, viem, PostgreSQL +
  Prisma
- **`keeper-bot/`** — Node.js, TypeScript, viem
- **`frontend/`** — React, Vite, TypeScript, wagmi, viem

## Current Product Capabilities

**Order Lifecycle**
- Create, cancel, and execute orders with checks-effects-interactions and
  `ReentrancyGuard` on every fund-moving path
- Pull-over-push refunds and keeper fee payout

**Price Verification & Execution Safety**
- Price condition re-verified on-chain against Chainlink inside
  `executeOrder()` — the keeper bot is never trusted as a price source
- Slippage protection (`maxSlippageBps`) confirmed working under a real
  revert during live testing, not just in unit tests

**Indexing & Monitoring**
- Indexes `OrderCreated` / `OrderExecuted` / `OrderCancelled` into
  PostgreSQL via Prisma
- Read-only, CORS-enabled REST API (`GET /orders`, optional `?status=`
  filter) — no private key held
- Chunked `eth_getLogs` backfill with exponential 429 backoff and a
  proactive inter-chunk throttle
- Live event watching via direct `eth_getLogs` polling, not viem's
  filter-based `watchContractEvent` (unreliable against Alchemy's free
  tier)

**Frontend**
- Wallet connect via wagmi's injected connector
- Order creation form (asset defaults to WETH, condition, USD target
  price, ETH deposit, slippage, expiry)
- Order list scoped to the connected wallet, with live status
- Cancellation for pending orders

**Testing & Deployment**
- 100% test coverage on `contracts/` (62 tests, 66 with the fork suite)
  across unit, fork, fuzz, and invariant categories
- Slither-clean `src/` — every finding triaged, fixed or
  documented-suppressed
- Deployed and verified on Sepolia Etherscan: OrderKeeper
  `0x2d065b6a75A207e73Cc9f76953A5886B250336FD`, DemoUSDC
  `0xDB7B8e1c83b14e3E4585FFb2b03088c0520b0568`

---

## Current Development Focus

**Status: ACTIVE**

With Milestone 13 (full test coverage) confirmed and shipped — 60 tests
across all three off-chain/frontend services, all passing in CI — the MVP
itself is now presentation-ready for Module 16. My focus shifts to
Milestone 14, Chainlink Automation as an alternative trigger source: the
first of the remaining post-MVP milestones, none of which block the
presentation.

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

Status: COMPLETED
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

# Milestone 14 - Chainlink Automation as Alternative Trigger Source

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

# Milestone 15 - Operational Monitoring/Alerting

Status: PLANNED
Depends on: Milestone 2, Milestone 3

Goals:
- Add uptime/health monitoring for `order-indexer` and `keeper-bot` in a
  persistent (non-local) deployment
- Add alerting on downtime (e.g. missed poll cycles, failed RPC/DB
  connections)
- Optional hardening — relevant once either service runs somewhere
  long-lived, not required for the Sepolia MVP demo

# Milestone 16 - Partial Order Fills / Additional Condition Types

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

# Milestone 17 - Mainnet or L2 Deployment

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

- Users can create and cancel orders against any asset with a verified
  Sepolia Chainlink feed, not just WETH
- The frontend shows live, on-chain-sourced pricing context before a user
  commits to a condition
- The UI works cleanly on both desktop and mobile
- `frontend/`, `order-indexer/`, and `keeper-bot/` all have real automated
  test coverage, matching `contracts/`'s existing bar
- The full stack remains verifiably trustless end-to-end: the keeper bot
  only ever triggers, the contract alone decides
