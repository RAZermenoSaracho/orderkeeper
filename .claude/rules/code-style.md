# Code Style

Solidity + TypeScript conventions for OrderKeeper. Pulled from `CLAUDE.md`'s
"Conventions" section — treat that section as the source of truth if this
ever drifts out of sync.

## Language

Every non-negotiable rule about language (English-only, no exceptions) lives
in [security.md](security.md), rule (b) — not duplicated here.

## NatSpec

NatSpec is mandatory on every public/external Solidity function: `@notice`,
`@dev`, `@param`, `@return` where applicable.

## Requirement / Spec IDs

If code maps to a bootcamp assignment spec, tag inline at the exact line of
fulfillment, e.g. `// OK-01: ...` — not in a block comment above the
function.

## Security posture (coding-level)

- Checks-effects-interactions on every fund-moving function.
- `ReentrancyGuard` wherever external calls are involved.
- Pull-over-push for payments.
- `order-indexer` is read-only by design — no private keys, ever. (For the
  absolute rule on secrets in general, see
  [security.md](security.md), rule (a).)

## Simplicity

Avoid over-engineering. Prefer the simplest design that satisfies the
requirement over a more "impressive" but harder to test/maintain one.
