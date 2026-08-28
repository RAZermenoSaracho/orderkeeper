# CLAUDE.md — keeper-bot/

Local agent orientation for `keeper-bot/`. Read the root `CLAUDE.md`
first; this file only covers conventions specific to this directory.

---

## Testing

- **Stack**: Vitest (`vitest.config.ts`, `environment: "node"`). `npm test`
  / `npm run test:coverage`.
- **Co-located test files**: `file.test.ts` next to `file.ts` (e.g.
  `src/keeper.test.ts`), not a separate `__tests__/` directory — same
  convention as `frontend/`/`order-indexer/`.
- **`chain.ts` must be fully mocked, not just stubbed after import** —
  it throws at module load time if `RPC_URL`/`PRIVATE_KEY` aren't set,
  which they won't be in a test environment. Use
  `vi.mock("./chain.js", () => ({ publicClient: {...}, walletClient: {...}, operatorAccount: {...} }))`
  before importing anything that transitively imports `chain.ts`.
- **Build real revert fixtures with `encodeErrorResult`/`ContractFunctionRevertedError`**
  when testing revert-reason handling (see `keeper.test.ts`'s
  `makeRevertError`), rather than hand-faking an object shape — this
  exercises `extractRevertReason()`'s actual ABI-decoding path via
  `BaseError.walk()`, not a shortcut that would pass even if the real
  decoding logic broke.
- **`tsconfig.json` excludes `src/**/*.test.ts`** from the production
  build (`npm run build`) — test files were leaking into `dist/` before
  this was added.

Decided 2026-08-28, during Milestone 13 (Full Test Coverage) in
`ROADMAP.md`.
