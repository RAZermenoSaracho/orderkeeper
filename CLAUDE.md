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

Early stage — architecture defined, no contracts or services implemented yet.
This file will be updated as each component comes online.

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
| `contracts/` | Foundry, OpenZeppelin (`IERC20`, `ReentrancyGuard`), Chainlink `AggregatorV3Interface`, Uniswap router interface |
| `order-indexer/` | Node.js, TypeScript, Fastify (REST API: `GET /orders`, `GET /orders/:id`), viem (`watchContractEvent`), SQLite/PostgreSQL |
| `keeper-bot/` | Node.js, TypeScript, viem (own operator wallet, separate from user funds) |
| `frontend/` | React, Vite, TypeScript (pure SPA, no SSR), viem, wagmi |

---

## Conventions

- **All code, comments, NatSpec, and identifiers are written in English** —
  no exceptions, regardless of the language used in conversation or commit
  discussion.
- **NatSpec is mandatory** on every public/external function — `@notice`,
  `@dev`, `@param`, `@return` where applicable.
- **Requirement/spec IDs**, if this project maps to a bootcamp assignment
  spec, are tagged inline at the exact line of fulfillment (e.g. `// OK-01: ...`),
  not in block comments above the function.
- **Security posture**: checks-effects-interactions on every fund-moving
  function, `ReentrancyGuard` where external calls are involved, pull-over-push
  for payments, no private keys in the `order-indexer` (it is read-only by
  design).
- **Simplicity preference**: avoid over-engineering. Prefer the simplest
  design that satisfies the requirement over a more "impressive" but harder
  to test/maintain one.

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
`docs`, `gitignore`, `readme` — add to this list as new scopes appear rather
than inventing new naming patterns ad hoc.

Example: `feat(contracts): add order execution with Chainlink verification`

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

## Open Design Questions

- Should `keeper-bot` read pending orders directly from the contract (no
  dependency, slower) or from `order-indexer` (faster, but must stay in
  sync)? Currently leaning toward `order-indexer` first, with a fallback path
  to direct contract reads if freshness becomes a concern.
- Uniswap V2 vs V3 router — not yet decided.
- `order-indexer` database: SQLite (simpler) vs PostgreSQL (more robust) —
  not yet decided.

---

## Environment Variables

Each service will have its own `.env` (never committed — see `.gitignore`).
Expected variables, to be finalized as each service is built:

- `RPC_URL` — Sepolia RPC (Alchemy, WebSocket-capable for `order-indexer` and
  `keeper-bot`)
- `PRIVATE_KEY` — deployer key (`contracts/`) and operator key
  (`keeper-bot/`) — **never share the same key between services**
- `CHAINLINK_ETH_USD_FEED` — Sepolia feed address
- `UNISWAP_ROUTER_ADDRESS` — Sepolia router address