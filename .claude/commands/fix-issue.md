---
description: Fix a described bug or issue
argument-hint: <description of the bug or issue>
---

Fix the following issue in OrderKeeper:

$ARGUMENTS

Before changing anything:

1. Reproduce or clearly localize the root cause — don't patch symptoms.
2. Check `.claude/rules/code-style.md`, `.claude/rules/testing.md`, and
   `.claude/rules/security.md` for constraints that apply to the fix.

While fixing:

- Keep the change scoped to the issue — no unrelated refactoring or
  cleanup in the same pass.
- Add or update a test that would have caught this bug, per
  `.claude/rules/testing.md`.
- Follow the security rules in `.claude/rules/security.md` without
  exception (no hardcoded secrets, English-only).

After fixing, summarize the root cause and the fix in 2-3 sentences.
