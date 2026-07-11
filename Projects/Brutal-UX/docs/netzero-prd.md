# NetZero — Business Plan & PRD

**Product:** NetZero, a personal finance web app built on UX Brutalism.
**One-liner:** Your number, instantly. No graphs, no categories, no coaching.
**Demo:** `/netzero` route in the Brutal UX app.
**Status:** Plan, execution-ready.

## 1. Executive Summary & Value Proposition

Every mainstream finance app (YNAB, Monarch, the ghost of Mint) sells the same thing: emotional management of your money. Pie charts to make spending feel legible, streaks to make budgeting feel like a game, "You saved!" confetti to make you feel parented. The cost of that comfort is latency, density loss, and a subscription that renews whether you look at it or not.

The problem NetZero solves: people who already have financial discipline have no tool that respects it. The F.I.R.E. community runs their lives on one number, net liquidity, and every existing app buries that number under insight modules.

The psychological hook is brutal honesty as a feature. Craigslist proved a pure transactional ledger can dominate a market for decades. Pinboard proved people pay a raw fee for raw utility. NetZero applies the same economics to personal finance: you enter a transaction, the number changes in the same frame, and nothing else happens. The absence of comfort IS the value proposition. The app never softens a bad month. That severity builds more trust than any dashboard.

**Value proposition:** the fastest possible path from "money moved" to "I know exactly where I stand," with zero psychological middleware.

## 2. Core Feature Loop

Onboarding is one screen and zero tutorial:

1. Land on the app. One input: STARTING LIQUIDITY. Enter a number, hit SET. You are onboarded. Total elapsed time: under ten seconds.
2. Daily loop: DESCRIPTION + AMOUNT + one of two buttons, [+ INCOME] or [– EXPENSE]. Row appends to the ledger. Net liquidity recomputes in the same tick. No save button, no sync spinner, no category picker.
3. Review loop: the ledger is one rigid table, newest first, infinite scroll, filterable by plain text search. That is the entire analytical surface. Users who want analysis export CSV with one click and do it themselves. NetZero refuses to interpret your data for you.
4. Correction loop: every row has DELETE. Click it, the row is gone and the number is already updated. No undo toast. [verify: decide whether hard-delete with no undo survives user testing, or whether a 5-second re-add affordance is the acceptable ceiling]

There are no budgets, no goals, no categories, no recurring-transaction wizards in v1. If a feature does not change the number or record a transaction, it does not ship.

## 3. Brutal UX Constraints (frontend engineering rules)

- Palette: `#000000` on `#FFFFFF`. Negative net liquidity renders white on `#FF0000`. No other colors exist.
- Typography: system monospace stack only (`ui-monospace, "SF Mono", Menlo, Consolas, monospace`). The net figure renders at 64px bold; everything else 13 to 16px.
- Borders: `2px solid #000` on every interactive element and every table cell block. `border-radius: 0` enforced globally.
- Motion: none. `transition: none`, `animation: none` at the root. All state changes are synchronous DOM updates. A number that tweens is a number that lies about when it changed.
- Density: the ledger is a raw `<table>`. Row height set by line-height, not padding aesthetics. Target 25+ rows visible on a laptop screen.
- Copy: uppercase, declarative, no exclamation marks. Errors are a red border on the offending input, nothing else.
- Zero third-party UI dependencies beyond the base component layer. No chart libraries in the bundle, ever, as a build-enforced rule.

## 4. Monetization Strategy

No subscription traps, aligned with the philosophy or the product is a lie.

| Tier | Price | What it is |
|------|-------|------------|
| Local | $0 forever | Full ledger, local-first storage, CSV export. No account required. |
| Own Your Sync | $49 one-time | End-to-end encrypted sync across devices. Pay once, own it. |
| Bank Wire-Up | Raw pass-through | Optional bank sync billed at exact aggregator API cost (Plaid or Teller) plus a flat $1/month handling fee, itemized on the invoice. |

The pass-through line item is the marketing. No competitor will show users what the Plaid call actually costs. [verify: current Plaid/Teller per-connection pricing before publishing the number]

## 5. Go-To-Market & Marketing Copy

Channels: r/financialindependence, r/leanfire, Hacker News (Show HN), the Pinboard/Craigslist-appreciator crowd, F.I.R.E. bloggers who already publish their net worth as a raw number. The pitch to them is one screenshot: the giant number, the table, nothing else.

Homepage hero copy:

> **YOUR NET LIQUIDITY. NOTHING ELSE.**
>
> No pie charts. No streaks. No "great job this month."
> You enter a number. Your number changes. That is the entire product.
>
> Mint wanted you engaged. YNAB wanted you enrolled.
> NetZero wants you gone in eleven seconds, knowing exactly where you stand.
>
> [SET STARTING LIQUIDITY] — no email required.

Secondary line for ads and social: "Financial apps treat you like a child. This one treats you like an accountant."

## 6. Technical Architecture

Optimized for one thing: zero perceptible latency between input and the recomputed number.

- **Frontend:** React (Next.js static export or Vite SPA). State via a single reducer; net liquidity is a derived value computed synchronously on dispatch. No global state library.
- **Storage, local-first:** SQLite in the browser via wasm (or RxDB over IndexedDB) as the primary store. The app is fully functional offline and with zero account. The ledger never waits on a network round trip.
- **Sync (paid tier):** CRDT or append-only event log replicated to a thin backend (Cloudflare Workers + Durable Objects, or a small Postgres). Encryption client-side; the server stores ciphertext. Sync is background reconciliation, never in the input path.
- **Bank sync (optional):** aggregator webhooks land in a queue, transactions appear as pending rows the user confirms. Bank data never blocks manual entry.
- **Ledger math:** integer cents everywhere. No floats near money.
- **Performance budget:** first load under 50KB JS gzipped, input-to-DOM update under 16ms, enforced in CI.

**Next move:** validate the $49 one-time price against Pinboard's pricing history, then build the sync tier behind the already-shipped local-first demo.
