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
