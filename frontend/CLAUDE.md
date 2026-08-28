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
