# Testing Expectations

Pulled from `CLAUDE.md`'s "Testing Expectations (`contracts/`)" section —
treat that section as the source of truth if this ever drifts out of sync.

## `contracts/`

- **Unit tests** — full order lifecycle: create, execute, cancel,
  unauthorized access, edge cases (zero amounts, expired orders).
- **Fork tests** — against Sepolia state, real Chainlink feed, real Uniswap
  router.
- **Fuzz tests** — price/amount boundaries around the execution condition.
- **Invariant tests** — contract balance must always equal the sum of
  active order amounts (solvency).

Commands:

```
forge test
forge test --fork-url $RPC_URL   # fork tests
forge coverage                    # coverage
```

## Other services

No testing stack has been finalized yet for `order-indexer/`,
`keeper-bot/`, or `frontend/`. Update this file once one is chosen.
