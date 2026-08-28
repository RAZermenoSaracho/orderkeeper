# CLAUDE.md — frontend/

Local agent orientation for `frontend/`. Read the root `CLAUDE.md` first;
this file only covers conventions specific to this directory.

---

## File Structure

- **`src/App.tsx`** stays at the `src/` root, alongside `main.tsx`,
  `config.ts`, and `abi.ts` — it's the application root/entry component
  (rendered directly by `main.tsx`), not a reusable component.
- **`src/components/`** holds actual reusable UI components only
  (`CreateOrderForm.tsx`, `OrderList.tsx`, and any added later). Don't
  move `App.tsx` in here, even though it's a component in the React
  sense — the distinction is entry point vs. reusable piece, not "is it a
  component."

Decided 2026-08-28, during Milestone 9 (Mobile-Responsive Layout +
Component Reorganization) in `ROADMAP.md`.

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

Decided 2026-08-28, during Milestone 13 (Full Test Coverage) in
`ROADMAP.md`.
