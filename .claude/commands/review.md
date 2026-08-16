---
description: Request a code review pass on current changes
---

Review the current changes (`git diff` against the base branch, or the
files named below if given) against OrderKeeper's project rules:

- `.claude/rules/code-style.md` — Solidity + TypeScript conventions
- `.claude/rules/testing.md` — testing expectations for `contracts/`
- `.claude/rules/security.md` — the two non-negotiable rules (no hardcoded
  secrets, English-only)

Check specifically for:

1. NatSpec completeness on public/external Solidity functions.
2. Checks-effects-interactions ordering and `ReentrancyGuard` usage on any
   fund-moving function.
3. Any hardcoded secret, key, or RPC URL with an embedded key.
4. Any non-English text in code, comments, identifiers, or NatSpec.
5. Missing tests for new/changed behavior (unit, and fork/fuzz/invariant
   where applicable per `testing.md`).

Report findings by file and line. Don't fix anything unless asked —
review only.

Target: $ARGUMENTS
