# OrderKeeper

A decentralized limit-order keeper bot for EVM chains. Users deposit funds and define a price condition (e.g. "sell 1 ETH when price >= $4,000"); an off-chain keeper bot monitors Chainlink price feeds and automatically executes the swap via Uniswap when the condition is met, earning a small fee for the service.

---

## Problem Statement

Limit orders are a basic trading primitive on centralized exchanges, but on-chain DEXs (like Uniswap) only support market swaps — there's no native way to say "execute this trade only when price reaches X" without either trusting a centralized service or manually watching the market yourself.

OrderKeeper solves this trustlessly: funds are custodied by a smart contract, execution conditions are verified on-chain against a Chainlink oracle, and anyone can run the keeper bot that triggers execution — no centralized party holds funds or controls execution.

---

## Why This Project

- **Real income potential**: the keeper fee mechanism means this isn't just a demo — it's a monetizable service.
- **Architecturally simple, not over-engineered**: unlike MEV liquidation/arbitrage bots (which require simulating market conditions that don't organically exist on testnet), OrderKeeper works end-to-end on Sepolia using a real Chainlink feed and real Uniswap liquidity.
- **Trustless by design**: the bot only *triggers* execution — the contract independently re-verifies the price against Chainlink before moving any funds, so a compromised or buggy bot can never force a false execution.

---

## Architecture

Four components, each with a single responsibility (simple microservices over a monorepo):

```mermaid
flowchart TB
    User(["User's Wallet"])
    Frontend["frontend/<br/>React + Vite + wagmi"]
    Contracts["contracts/<br/>Foundry — Sepolia"]
    Indexer["order-indexer/<br/>Fastify REST API"]
    History[("indexed order history<br/>PostgreSQL + Prisma")]
    Keeper["keeper-bot/<br/>viem + operator key"]
    Chainlink[("Chainlink<br/>Price Feed")]

    User -- "signs tx" --> Frontend
    Frontend == "createOrder() / cancelOrder()<br/>(write, signed by user)" ==> Contracts
    Keeper == "executeOrder()<br/>(write, signed by keeper)" ==> Contracts
    Frontend -. "GET /orders<br/>(read-only)" .-> Indexer
    Indexer -. "GET /orders<br/>(pending orders)" .-> Keeper
    Keeper -. "checkPriceCondition()<br/>(free eth_call)" .-> Contracts
    Contracts -- "emits events" --> Indexer
    Indexer -- "persists" --> History
    Contracts == "re-verifies price on-chain<br/>at execution (trust boundary)" ==> Chainlink

    style Contracts fill:#2d2d2d,stroke:#666,color:#fff
    style Chainlink fill:#375bd2,stroke:#375bd2,color:#fff
```

Thick arrows = on-chain writes into `contracts/` (or the contract's own on-chain re-check of Chainlink); dashed arrows = off-chain reads and monitoring, which never touch the write path.

### 1. `contracts/` — On-chain core
Custodies order funds, verifies price conditions on-chain, executes swaps.
- **Stack**: Foundry, OpenZeppelin (`IERC20`, `ReentrancyGuard`), Chainlink `AggregatorV3Interface`, Uniswap V2 router interface
- **Core logic**: `createOrder()`, `executeOrder()` (re-validates price on-chain before executing), `cancelOrder()`, keeper fee on successful execution

### 2. `order-indexer/` — Event listener + read API
Listens for `OrderCreated` / `OrderExecuted` / `OrderCancelled` events, persists them, and exposes them over a REST API (e.g. `GET /orders`, `GET /orders/:id`) so the frontend and keeper don't need to query the chain directly on every read.
- **Stack**: Node.js, TypeScript, Fastify (REST API), viem (`watchContractEvent` over WebSocket), PostgreSQL + Prisma
- **Read-only**: never sends transactions, never holds a private key — smaller attack surface by design. It only serves reads of indexed history; it never sits in the write path — order creation and cancellation go directly from the frontend to the contract

### 3. `keeper-bot/` — Executor
Polls `order-indexer`'s REST API for pending orders (see Design Decisions), then re-checks each one's price condition via the contract's own `checkPriceCondition()` — a free `eth_call`, not an independent Chainlink read — before calling `executeOrder()`. This keeps the off-chain trigger logic from ever silently drifting apart from what `executeOrder()` itself re-verifies.
- **Stack**: Node.js, TypeScript, viem — holds its own operator private key (separate from user funds) to sign and send execution transactions

### 4. `frontend/` — User interface
Wallet connection, order creation/cancellation, order history and status.
- **Stack**: React + Vite + TypeScript (pure SPA, no SSR), viem, wagmi for wallet connection
- **Direct-to-contract writes**: order creation and cancellation are signed by the user's wallet and sent straight to the contract via wagmi/viem — the frontend talks to `order-indexer` only to read order history

---

## Security Considerations

- **Access control**: only the order owner can cancel their own order
- **Reentrancy protection**: `ReentrancyGuard` on any function moving funds; strict checks-effects-interactions ordering
- **Oracle trust boundary**: execution price is verified on-chain via Chainlink at execution time — the keeper bot is never trusted as a price source, only as a trigger
- **Key isolation**: the keeper bot's operator key is fully separate from user funds and from the indexer (which holds no key at all)

---

## Design Decisions

### Trigger vs. verification are separate concerns

Two things are often conflated in "keeper bot" designs, and OrderKeeper
deliberately keeps them separate:

- **(a) Who monitors price and triggers execution** — an off-chain process
  that watches the market and decides *when* to call `executeOrder()`.
- **(b) Where the price is verified before funds move** — this is
  non-negotiable and always happens on-chain, inside `executeOrder()`,
  directly against Chainlink. See [Security Considerations](#security-considerations)
  above for the full reasoning; in short, the keeper bot is trusted only as
  a trigger, never as a price source, so nothing about (a) can ever weaken
  (b).

Because (b) is fixed, the only real design question is (a): *which*
off-chain process gets to call `executeOrder()`.

### Trigger choice: self-run `keeper-bot`, not Chainlink Automation

For (a), OrderKeeper uses a self-run `keeper-bot` (`viem` + its own
operator private key) rather than Chainlink Automation.

This is a deliberate trade-off, not an oversight:

- **What Chainlink Automation would have bought us**: it runs independently
  of any machine I have to keep online, so uptime wouldn't depend on a
  personal bot staying up.
- **What it would have cost**: LINK funding to keep upkeeps running, and —
  more importantly for this project — loss of direct visibility into
  exactly how and when triggers fire, since that logic would live inside
  Chainlink's infrastructure instead of in a bot I wrote and can read
  end-to-end.
- **Why self-run won anyway**: architectural transparency and consistency
  with this project's simplicity preference (see `CLAUDE.md`'s
  Conventions) outweighed production-grade uptime here. This mirrors the
  same reasoning already applied to the time-check oracle pattern in the
  Module 13 `RWAAssetToken` assignment — understanding every moving part
  end-to-end matters more than uptime guarantees for a bootcamp capstone,
  which is not a live production service.

### This is a reversible choice

Chainlink Automation remains a valid future upgrade path if uptime becomes
a real concern post-MVP. Swapping the trigger source doesn't require
redesigning `executeOrder()`'s on-chain verification logic — that logic
doesn't care who calls it, only that the price it independently re-checks
against Chainlink is correct at call time. This door is intentionally left
open, not closed.

### `keeper-bot`'s order source: `order-indexer`, not direct contract reads

`keeper-bot` reads pending orders from `order-indexer`'s REST API rather
than querying the contract directly — faster reads, at the cost of
`keeper-bot` now depending on the indexer staying online and in sync.
Decided during scaffolding (2026-08-16); direct contract reads remain a
fallback path if indexer freshness ever becomes a concern.

---

## On-Chain Activity

Deployed contract addresses live in `deployments/sepolia.json`. The full
create-to-execute loop has been run for real on Sepolia — not just in
tests — with `order-indexer` and `keeper-bot` both running as long-lived
services, mirroring how Module 13's `updatePrice()` was proven live rather
than only unit-tested.

**Verified end-to-end (2026-08-17)**: a 0.001 ETH order with a
trivially-true condition (target price $1,000, live price ~$1,907) was
created and executed in back-to-back blocks — `keeper-bot` caught it on
its very first poll after `order-indexer` picked up the `OrderCreated`
event.

- **`createOrder()` tx**: [`0x71945d01dd3589745bc41113afc325d2b1fa67514379d9a0efa0ba4d52c3b2f7`](https://sepolia.etherscan.io/tx/0x71945d01dd3589745bc41113afc325d2b1fa67514379d9a0efa0ba4d52c3b2f7) — block `11509603`
- **`executeOrder()` tx**: [`0x3686d6b77f04fb0fa09bf27878753efebe63972b53fb5a1ff81ba08638ae737f`](https://sepolia.etherscan.io/tx/0x3686d6b77f04fb0fa09bf27878753efebe63972b53fb5a1ff81ba08638ae737f) — block `11509604`, the very next block
- **`executionPrice`**: `1907173604190000000000` (≈ $1,907.17, matching the
  live oracle read used to size the order)
- **`keeperFee`**: `5000000000000` (0.000005 ETH — 0.5% of the 0.001 ETH
  order, per `KEEPER_FEE_BPS`)
- **`amountOut`**: `1887231` (≈ 1.887231 DemoUSDC, 6 decimals)

This run also caught a real process bug before it mattered:
`keeper-bot`'s operator key had initially been reused from the
`contracts/` deployer key, violating CLAUDE.md's "never share keys
between services" rule. Caught and fixed by generating a fresh operator
wallet (`0x9B7beaD9A83903387373EeaA241a9D82598022F3`) before this run.

To reproduce this yourself, or re-verify after future changes, see
[`RUNBOOK.md`](RUNBOOK.md)'s "End-to-end oracle loop verification" workflow.

---

## Testing Plan

- **Unit tests** (Foundry) — order lifecycle: create, execute, cancel, unauthorized access, edge cases (zero amounts, expired orders)
- **Fork tests** — against Sepolia state, using the real Chainlink feed and Uniswap router
- **Fuzz tests** — price/amount boundaries around the execution condition
- **Invariant tests** — contract balance always matches the sum of active order amounts (solvency)

---

## Roadmap (Bootcamp Timeline)

| Modules | Milestone | Status |
|---|---|---|
| 09–12 | Planning: architecture, contract design | This document |
| 12 | Project pitch | Tomorrow |
| 13–16 | Build: contracts + frontend + tests | Upcoming |
| 16 | MVP presentation | Upcoming |