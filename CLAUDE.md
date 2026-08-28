# CLAUDE.md

Agent orientation file for OrderKeeper. Read this before making changes.

---

## Project Summary

OrderKeeper is a trustless limit-order keeper bot for EVM chains. Users deposit
funds and define a price condition; an off-chain keeper bot monitors a
Chainlink price feed and triggers on-chain execution via Uniswap when the
condition is met. The smart contract independently re-verifies the price
against Chainlink at execution time — the keeper bot is trusted only as a
trigger, never as a price source.

This is a Metana Web3 bootcamp capstone project (cohort sol81), presented at
Module 12 (pitch) and Module 16 (MVP).

Full context: `README.md`.

---

## Status

`contracts/` has full business logic: `OrderKeeper.sol` (order lifecycle,
Chainlink oracle verification, Uniswap V2 execution) and `DemoUSDC.sol` (a
testnet-only quote token). 62 tests pass by default (`forge test`; the
fork suite self-skips without `RPC_URL` — all 66 pass with
`--fork-url sepolia`), covering unit, fork, fuzz, and invariant categories.
Both contracts are at 100% coverage and `slither`-clean — findings against
`src/` are triaged (fixed if real, suppressed with a documented rationale
if accepted by design; see Conventions). Deployed and verified end-to-end
on Sepolia — see README.md's On-Chain Activity section.

`order-indexer/` and `keeper-bot/` have working implementations — event
indexing + REST API, and the poll/check/execute loop, respectively — and
were audited and fixed this session: hardening included CORS support,
consistent `{error:{code,message}}` error handling, fixed `Decimal`
serialization (was breaking `BigInt()` parsing above $1,000 asset
prices), a fetch timeout and top-level error handling in `keeper-bot`,
and replacing `order-indexer`'s filter-based `watchContractEvent` (proved
unreliable against Alchemy's free tier) with direct `eth_getLogs`
polling.

`frontend/` has a working MVP — wallet connect, order creation, order
list, and cancellation — verified against a live Sepolia deployment (see
README.md's On-Chain Activity section).

This file will be updated as each component's state changes.

---

## Agent Files

Agent-specific configuration lives under `.claude/`:

```
.claude/
├── settings.json          # baseline tool permissions, hook wiring
├── settings.local.json    # personal overrides (gitignored)
├── rules/                 # code-style.md, testing.md, api-conventions.md, security.md
├── commands/               # /review, /fix-issue slash commands
├── skills/deploy/          # deployment workflow (stub until contracts/ exists)
├── skills/resolve-issues/  # works through ISSUES.md entries you select
├── agents/                 # code-reviewer, security-auditor sub-agents
└── hooks/validate-bash.sh  # blocks staged hardcoded-secret patterns
```

`.claude/rules/security.md` holds the two non-negotiable rules (no
hardcoded secrets, English-only) referenced from Conventions below.
`CLAUDE.local.md` (gitignored, repo root) is for machine-specific notes.
`RUNBOOK.md` (repo root) is a home for **manual** verification workflows
Ricardo runs himself (e.g. against live Sepolia) — an agent should not
execute any of them unprompted; several involve real Sepolia ETH and real
transactions.

---

## Planned Structure

```
orderkeeper/
├── contracts/          # Foundry — order custody, Chainlink verification, Uniswap execution
├── order-indexer/      # Node/TS + Fastify — listens to contract events, persists them, exposes REST API (read-only, no private key)
├── keeper-bot/         # Node/TS — monitors price, calls executeOrder() (holds operator private key)
├── frontend/           # React + Vite + TS + viem + wagmi — wallet connect, order creation/management (writes go directly to the contract, signed by the user's wallet)
└── deployments/        # Deployed contract addresses per chain/environment
```

Each service is independent — no shared monorepo tooling (npm workspaces,
turborepo, etc.) unless a real need for shared types emerges. Prefer
duplication over premature abstraction at this stage.

---

## Tech Stack

| Component | Stack |
|---|---|
| `contracts/` | Foundry, OpenZeppelin (`IERC20`, `ReentrancyGuard`), Chainlink `AggregatorV3Interface`, Uniswap V2 router interface |
| `order-indexer/` | Node.js, TypeScript, Fastify (REST API: `GET /orders`, `GET /orders/:id`), viem (`watchContractEvent`), PostgreSQL + Prisma |
| `keeper-bot/` | Node.js, TypeScript, viem (own operator wallet, separate from user funds) |
| `frontend/` | React, Vite, TypeScript (pure SPA, no SSR), viem, wagmi |

---

## Conventions

- **English-only and no hardcoded secrets are non-negotiable** — see
  `.claude/rules/security.md` for both rules in full; not repeated here.
- **NatSpec is mandatory** on every public/external function — `@notice`,
  `@dev`, `@param`, `@return` where applicable.
- **Requirement/spec IDs**, if this project maps to a bootcamp assignment
  spec, are tagged inline at the exact line of fulfillment (e.g. `// OK-01: ...`),
  not in block comments above the function.
- **Security posture**: checks-effects-interactions on every fund-moving
  function, `ReentrancyGuard` where external calls are involved, pull-over-push
  for payments, no private keys in the `order-indexer` (it is read-only by
  design).
- **Slither is part of the security workflow**: run via
  `slither contracts/src/` — only `src/`; findings in `lib/` are external
  dependencies, out of scope. Findings against `src/` are triaged: fixed
  if real, or suppressed with a `// slither-disable-next-line
  <detector-id>` comment plus a one-line `@dev`-style rationale directly
  above the flagged line if accepted by design. Never suppressed silently.
- **Simplicity preference**: avoid over-engineering. Prefer the simplest
  design that satisfies the requirement over a more "impressive" but harder
  to test/maintain one.
- **First-person authorial voice outside Claude-specific files**: in
  `README.md` and other project content (excluding `CLAUDE.md`,
  `CLAUDE.local.md`, and `.claude/`), write as Ricardo authoring the
  document — "I decided," "I wrote," never "Ricardo decided," "Ricardo
  wrote." Inside Claude-specific files, third-person references to
  Ricardo by name remain correct (e.g. "Ricardo should verify this
  manually" makes sense in an agent-facing instruction file; it wouldn't
  in the README). `@author Ricardo` in Solidity NatSpec is a standard
  convention, not narrative voice, and is exempt either way.

### Commit Convention

Follows [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

`type` is one of:

| Type | Meaning |
|---|---|
| `feat` | new functionality (a new contract function, endpoint, UI screen) |
| `fix` | bug fix |
| `docs` | documentation-only changes (README, CLAUDE.md, comments) |
| `chore` | maintenance with no logic impact (`.gitignore`, configs, dependencies) |
| `test` | adding or modifying tests, no production code changes |
| `refactor` | restructuring existing code without changing behavior |
| `style` | formatting only, no logic change |
| `perf` | performance improvement |
| `build` | build system or external dependency changes (Foundry config, `package.json`) |
| `ci` | CI/CD pipeline changes |
| `revert` | reverting a previous commit |

Common scopes so far: `contracts`, `order-indexer`, `keeper-bot`, `frontend`,
`docs`, `gitignore`, `readme`, `claude-code`, `issues`, `mcp`,
`deployments`, `runbook` — add to this list as new scopes appear rather
than inventing new naming patterns ad hoc.

Example: `feat(contracts): add order execution with Chainlink verification`

#### Atomic commits (standing rule)

Commits are atomic: **one file, or one tightly-coupled change** (e.g. a
`rules/` file plus the single cross-reference edit it requires elsewhere),
**per commit**. Never bundle unrelated files into a single commit, even if
they landed in the same session or task.

Format: `action(scope): description`, where `action` is the Conventional
Commits type from the table above and `scope` matches the component
touched (e.g. `claude-code`, `gitignore`, `docs`).

This applies every time, in every future session, without needing to be
repeated.

---

## Architectural Decision Documentation

Whenever implementation work involves a real architectural or structural
decision — not a trivial implementation detail, but something a future
session would need to know to stay consistent (e.g. how tests are
organized in a service, a naming/folder convention, a library choice with
tradeoffs, a pattern for handling a recurring problem) — STOP and ask
Ricardo before deciding unilaterally. Do not guess or silently pick an
approach for anything that qualifies as a standing convention.

Once confirmed, document it in the most locally-relevant place:

- Decisions scoped to one service (`contracts/`, `order-indexer/`,
  `keeper-bot/`, `frontend/`) go in that service's own `CLAUDE.md` if one
  exists, or should prompt creating one if the decision is significant
  enough to need local, always-loaded context for future work in that
  directory (e.g. a testing architecture, a component structure
  convention).
- Decisions spanning the whole repo go in this root `CLAUDE.md`'s Design
  Decisions section, following the existing entries' format (what was
  decided, why, when).
- `ROADMAP.md` tracks WHAT will be built and in what order; `CLAUDE.md`
  files track HOW and WHY, for agent orientation. Don't conflate the two.

Example trigger: choosing `frontend/`'s test file organization convention
(e.g. co-located `*.test.tsx` vs a `__tests__/` directory) during
Milestone 12 should produce a `frontend/CLAUDE.md` documenting that
choice, not just an implementation that happens to follow some ad-hoc
pattern.

---

## Testing Expectations (`contracts/`)

- **Unit tests** — full order lifecycle: create, execute, cancel, unauthorized
  access, edge cases (zero amounts, expired orders)
- **Fork tests** — against Sepolia state, real Chainlink feed, real Uniswap
  router
- **Fuzz tests** — price/amount boundaries around the execution condition
- **Invariant tests** — contract balance must always equal the sum of active
  order amounts (solvency)

Run with `forge test`, fork tests with `forge test --fork-url $RPC_URL`,
coverage with `forge coverage`.

---

## Design Decisions

- **Trigger vs. verification are separate concerns.** Who triggers
  execution (off-chain) and where price is verified before funds move
  (always on-chain, inside `executeOrder()`, against Chainlink) are
  distinct — the latter is non-negotiable, see `README.md`'s Security
  Considerations.
- **Trigger choice: self-run `keeper-bot`, not Chainlink Automation.**
  Automation would run more reliably without a personal bot needing to
  stay online, at the cost of LINK funding and losing direct visibility
  into how triggers fire. Self-run was chosen for architectural
  transparency and this project's simplicity preference — same reasoning
  as the Module 13 `RWAAssetToken` time-check oracle pattern. Full detail
  and rationale: `README.md`'s "Design Decisions" section.
- **Reversible**: Chainlink Automation remains a valid post-MVP upgrade if
  uptime becomes a concern — swapping the trigger source doesn't require
  redesigning `executeOrder()`'s verification logic.
- **`keeper-bot` reads pending orders from `order-indexer`'s REST API**,
  not directly from the contract — faster reads, at the cost of depending
  on the indexer staying online and in sync. Decided 2026-08-16 during
  scaffolding.
- **Uniswap V2**, not V3 — simpler router interface (no concentrated-
  liquidity/tick math), matching this project's simplicity preference;
  Sepolia has enough V2 liquidity for a capstone demo. Decided 2026-08-16.
- **`order-indexer` uses PostgreSQL + Prisma**, not SQLite — Ricardo
  already runs PostgreSQL locally, so SQLite's zero-setup advantage
  doesn't apply, and this avoids a future migration if the project outlives
  the bootcamp demo. Decided 2026-08-16.
- **`order.asset` is oracle-only, never the swap target.** `executeOrder()`
  always swaps `weth` (resolved from `uniswapRouter.WETH()` at
  construction, immutable) for `quoteToken` — `order.asset` only selects
  which Chainlink feed the price condition is checked against. Necessary
  because deposits are always ETH-denominated regardless of which asset
  prices the condition; conflating the two would make Uniswap V2 revert
  (it requires `path[0]` to be its own `WETH()` address) for any order
  whose asset wasn't literally WETH. Decided 2026-08-17.

---

## Open Design Questions

None currently open — see Design Decisions above. New questions get added
here as they come up.

---

## Environment Variables

Each service will have its own `.env` (never committed — see `.gitignore`).
Expected variables, to be finalized as each service is built:

- `RPC_URL` — Sepolia RPC (Alchemy, WebSocket-capable for `order-indexer` and
  `keeper-bot`)
- `PRIVATE_KEY` — deployer key (`contracts/`) and operator key
  (`keeper-bot/`) — **never share the same key between services**
- `CHAINLINK_ETH_USD_FEED` — Sepolia feed address, used by `contracts/`'s
  deploy script to register the feed. **Not** used by `keeper-bot` —
  it calls `OrderKeeper.checkPriceCondition()` on-chain instead of reading
  Chainlink directly, so the off-chain trigger can never drift from what
  `executeOrder()` actually re-verifies.
- `UNISWAP_ROUTER_ADDRESS` — Sepolia V2 router address
- `DATABASE_URL` — `order-indexer`'s PostgreSQL connection string (Prisma).
  Local dev DB name: `orderkeeper_dev`.
- `PORT` — `order-indexer`'s HTTP listen port. Optional, defaults to `3001`.
- `GETLOGS_BLOCK_RANGE` — `order-indexer`'s `eth_getLogs` chunk size during
  backfill, to stay under provider block-range limits (e.g. Alchemy's free
  tier caps at 10). Optional, defaults to `10`.
- `BACKFILL_DELAY_MS` — `order-indexer`'s delay between backfill chunks, to
  stay under the RPC provider's rate limit proactively. Optional, defaults
  to `200`.
- `WATCH_POLL_INTERVAL_MS` — `order-indexer`'s interval between live
  event-watching polls (plain `eth_getLogs`, not viem's filter-based
  `watchContractEvent` — Alchemy's free tier doesn't reliably support
  `eth_newFilter`/`eth_getFilterChanges`). Optional, defaults to `15000`.
- `INDEXER_URL` — `keeper-bot`'s base URL for `order-indexer`'s REST API.
- `ETHERSCAN_API_KEY` — used by `RUNBOOK.md`'s "Verify contract on
  Etherscan" workflow (`forge verify-contract`). Free at
  https://etherscan.io/apis. Not yet added to `contracts/.env.example`.

`frontend/` needs `VITE_RPC_URL` and `VITE_CONTRACT_ADDRESS` as well —
added during scaffolding, not yet reviewed as carefully as the rest of
this list since wallet-connect/config work hasn't started.