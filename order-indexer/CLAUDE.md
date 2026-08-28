# CLAUDE.md — order-indexer/

Local agent orientation for `order-indexer/`. Read the root `CLAUDE.md`
first; this file only covers conventions specific to this directory.

---

## Testing

- **Stack**: Vitest (`vitest.config.ts`, `environment: "node"`). `npm test`
  / `npm run test:coverage`. Migrated from `node:test` — see
  `src/routes/orders.test.ts`'s git log if you need the original version
  for reference.
- **Co-located test files**: `file.test.ts` next to `file.ts` (e.g.
  `src/routes/orders.test.ts`), not a separate `__tests__/` directory —
  same convention as `frontend/`.
- **`tsconfig.json` excludes `src/**/*.test.ts`** from the production
  build (`npm run build`) — test files were leaking into `dist/` before
  this was added. Keep this exclude if you add more test files elsewhere
  in `src/`.
- **No live DB/RPC in unit tests**: `serializeOrder()` is pure (no Prisma
  calls), so its tests construct an `Order` fixture directly rather than
  hitting Postgres. If you add tests that need a real database, that's a
  different tier (integration, not unit) — don't default to spinning one
  up in CI without deciding that deliberately first.

Decided 2026-08-28, during Milestone 13 (Full Test Coverage) in
`ROADMAP.md`.
