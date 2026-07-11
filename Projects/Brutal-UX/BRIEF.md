# Brutal UX — Brief

## Goal
Execute the "Brutal UX" (UX Brutalism) project: a design system + microsite + three product plans built on raw economic principles (efficiency, utility, scarcity), rejecting psychology-driven UX.

Source brief: `Vault_Brain/Raw_Notes/Brutal-UX.md`.

Three phases:
1. Repo + design-system foundation (Next.js + shadcn, oklch binary-contrast tokens).
2. Single-page component dashboard/sandbox: manifesto + tokens, component repository, functional "No-Bullsh*t Ledger" specimen.
3. Three execution-ready business plans + PRDs with demo routes: NetZero (F.I.R.E. budget ledger), Terminal Red (SRE incident command), StarkText (anti-platform publishing).

## Non-Goals
- GitHub publishing (local repo only for now).
- Custom web fonts, animations, gradients, rounded corners — forbidden by the design system.
- Vega HTML template compliance — this project intentionally uses its own design system (documented exception).

## Constraints
- Typography: system fonts only (monospace / system-ui).
- Palette: #000 / #FFF binary contrast; utility colors (#FF0000, #00FF00) for active/alert states only.
- Borders: 2px solid #000 everywhere; 3px section dividers; border-radius: 0.
- Interactions: zero transitions/animations; instant DOM changes.

## Stack
Next.js (App Router, TS, Tailwind v4) + shadcn/ui, scaffolded via `npx shadcn init --preset b1oVxvbG --template next`. Nested independent git repo at `app/` (gitignored by workspace repo).

## Acceptance Criteria
- [ ] `npm run build` passes in `app/`.
- [ ] `/` dashboard: 3 sections divided by 3px rules; working slapstick button; working ledger (add/delete/instant total).
- [ ] `/netzero`, `/terminal-red`, `/starktext` demo routes functional.
- [ ] `docs/` contains three PRDs, each with all six required sections.

## Status
active

| Date | Update |
|------|--------|
| 2026-07-09 | Project created; scaffold + build executed per approved plan. |
