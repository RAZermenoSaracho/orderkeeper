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
bootcamp repo, not a public one. Once Ricardo publishes that module to his
own GitHub, update both references to link directly to the relevant
contract (the price staleness/decimal-normalization logic being reused for
OrderKeeper's oracle verification) so the reasoning cited for the self-run
keeper-bot decision is independently checkable.

---
