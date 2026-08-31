# CLAUDE.md — frontend/

Local agent orientation for `frontend/`. Read the root `CLAUDE.md` first;
this file only covers conventions specific to this directory.

---

## File Structure

- **`src/App.tsx`** stays at the `src/` root, alongside `main.tsx`,
  `config.ts`, and `abi.ts` — it's the application root/entry component
  (rendered directly by `main.tsx`), not a reusable component. `App.tsx`
  itself renders only `<Layout />`, kept thin so `main.tsx`'s render
  target stays stable if the top-level composition changes again.
- **`src/layout/Layout.tsx`** owns the actual top-level UI composition
  (header, wallet control) and the wallet-state-dependent rendering:
  disconnected users see `Onboarding`; connected users see the order
  creation form and order list.
- **`src/components/`** holds actual reusable UI components only
  (`CreateOrderForm.tsx`, `OrderList.tsx`, `Onboarding.tsx` — wallet/
  Sepolia/test-funding guidance shown to disconnected users — and any
  added later). Don't move `App.tsx` in here, even though it's a
  component in the React sense — the distinction is entry point vs.
  reusable piece, not "is it a component."

Decided 2026-08-28, during Milestone 9 (Mobile-Responsive Layout +
Component Reorganization) in `ROADMAP.md`; `src/layout/` and
`Onboarding.tsx` added afterward as part of the wallet onboarding work.

---

## Testing

- **Stack**: Vitest + React Testing Library + `jsdom` (`vite.config.ts`'s
  `test` block; `src/test/setup.ts` loads `@testing-library/jest-dom`'s
  matchers). `npm test` / `npm run test:coverage`.
- **Co-located test files**: `Component.test.tsx` next to `Component.tsx`
  (e.g. `src/components/CreateOrderForm.test.tsx`), not a separate
  `__tests__/` directory.
- **Mock `wagmi`'s hooks directly** (`vi.mock("wagmi", async (importOriginal) => ({ ...await importOriginal(), useWriteContract: vi.fn(), ... }))`),
  rather than standing up a real wallet connection or a mocked JSON-RPC
  transport. This tests component behavior given various hook states
  (idle/pending/success/error), not wagmi's own internals — wagmi already
  tests those. Spread `importOriginal()` first so unmocked exports (types,
  `WagmiProvider`, etc.) still work.
- **Leave `@tanstack/react-query` and `fetch()` real** where a component
  uses them directly (e.g. `OrderList`'s `useQuery`/`fetchOrders`) — mock
  `global.fetch` via `vi.stubGlobal("fetch", ...)` instead of mocking
  `useQuery` itself, so the component's actual fetch/parse/filter logic is
  exercised, not bypassed. Wrap the component under test in a real
  `QueryClientProvider` (`new QueryClient({ defaultOptions: { queries: { retry: false } } })`
  — disable retries so a deliberately-failing test doesn't hang).
- **Partial mock return values need `as unknown as ReturnType<typeof wagmi.useX>`**,
  not a single-step cast — wagmi's hook return types are large
  discriminated unions (idle/pending/success/error variants with mutually
  exclusive fields), and a test only ever needs a handful of those fields
  per case.
- **`config.ts` throws at module load if `VITE_RPC_URL`, any of the three
  deployment addresses (`VITE_CONTRACT_ADDRESS`, `VITE_WETH_ADDRESS`,
  `VITE_QUOTE_TOKEN_ADDRESS`), or `VITE_INDEXER_URL` aren't set — correctly,
  for real runtime use — but
  `.env` is gitignored, so CI and a fresh clone have neither.** Any test
  file that imports a component importing `config.ts` for real (not every
  test mocks it away — `CreateOrderForm`/`OrderList`'s tests assert against
  the real deployment-address exports) would otherwise
  fail before a single test runs, not just get a wrong value. Fixed via
  `vite.config.ts`'s `test.env` — confirmed empirically (not assumed) that
  it does populate `import.meta.env.VITE_X` for Vitest, by running the
  suite with `frontend/.env` removed entirely and watching it still pass.
  Chose this over a `.env.test` file: it's colocated with the rest of the
  test config already in `vite.config.ts` rather than a new dotfile to
  know about, and it avoids implying these dummy values follow the same
  "copy and fill in real values" convention as `.env`/`.env.example`. Do
  **not** fix this kind of failure by relaxing `config.ts`'s validation —
  a genuinely missing env var in a real run should still fail loudly.

Decided 2026-08-28, during Milestone 13 (Full Test Coverage) in
`ROADMAP.md`; the `test.env` fix decided 2026-08-29.
