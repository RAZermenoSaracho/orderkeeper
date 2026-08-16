---
name: resolve-issues
description: Reads ISSUES.md, shows open issues, and works through resolving whichever ones you select — updating each entry's status in place. Invoke after finishing a scoped task to work through the backlog it left behind.
---

# Resolve Issues

1. Read `ISSUES.md` at repo root. If it doesn't exist, say so and stop —
   don't create it implicitly.
2. Parse all entries tagged `[OPEN]`. Print them as a numbered list:
   number, title, component, discovered date. If there are none, say so
   and stop.
3. Ask which ones to work on now (accept a number list, "all", or a
   subset by component) — an optional `args` value (e.g.
   `/resolve-issues 1,3` or `/resolve-issues all`) skips this prompt.
4. For each selected issue, in order:
   a. Re-read its full description — that's the only context available,
      don't assume anything beyond it.
   b. If the fix is ambiguous or has more than one reasonable approach,
      ask before proceeding — don't guess.
   c. Apply the fix, following whatever rules in `.claude/rules/` apply
      to the affected component (code-style, testing, security — always
      non-negotiable per `security.md`).
   d. Update the entry in `ISSUES.md`: change `[OPEN]` to `[RESOLVED]` or
      `[WON'T-FIX]`, set **Status** accordingly, add a **Resolved** line
      with today's date and a one-line summary of what was done or why it
      won't be fixed. Leave the rest of the entry untouched.
   e. Commit the fix and its `ISSUES.md` status update together, as one
      atomic commit (tightly-coupled change, same as a rules file plus
      its cross-reference) — `action(scope): description` per CLAUDE.md's
      commit convention. Use a separate commit per issue, even within the
      same invocation.
5. After all selected issues are handled, summarize what was resolved,
   what's still open, and anything marked won't-fix with the reason.
