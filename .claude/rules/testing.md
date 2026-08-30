# Testing Expectations

Pulled from `CLAUDE.md`'s "Testing Expectations (`contracts/`)" section —
treat that section as the source of truth if this ever drifts out of sync.

## `contracts/`

- **Unit tests** — full order lifecycle: create, execute, cancel,
  unauthorized access, edge cases (zero amounts, expired orders).
- **Fork tests** — against Sepolia state, real Chainlink feed, real Uniswap
  router.
- **Fuzz tests** — price/amount boundaries around the execution condition.
- **Invariant tests** — solvency per custodied asset: ETH balance matches
  the sum of active Sell orders' amounts, `quoteToken` balance matches
  the sum of active Buy orders' amounts, and the router is left with no
  stranded allowance after execution.

Commands:

```
forge test
forge test --fork-url $RPC_URL   # fork tests
forge coverage                    # coverage
```

## `order-indexer/`, `keeper-bot/`, `frontend/`

Vitest across all three, one unified toolchain rather than splitting
`node:test` and Vitest across the repo (`frontend/` additionally uses
React Testing Library). Commands are the same in each: `npm test` / `npm
run test:coverage`. See each service's own `CLAUDE.md` for
directory-specific testing conventions (mocking patterns, file
organization) — this file only tracks the stack choice itself.

Decided 2026-08-28, during Milestone 13 (Full Test Coverage) in
`ROADMAP.md`.
