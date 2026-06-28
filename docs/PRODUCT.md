# PRODUCT.md — Agent Workspace Template microsite

The GitHub Pages microsite for the **Agent Workspace Template**: a one-person,
multi-agent operating environment for Claude Code. The site has two surfaces.

## Surfaces & register

- **`index.html` — register: brand / landing.** Design IS the product here. It
  sells and explains the template to developers evaluating it: hero, the
  three-layer model, the agent roster, quick start, automation, a documentation
  map, and prerequisites. Confident, technical, editorial — not a generic SaaS
  landing page.
- **`health.html` — register: product / dashboard.** Design SERVES the data. A
  live system-health dashboard rendered from `status.js` (`window.__STATUS__`),
  grouped by architecture layer with pass/warn/fail rollups. Scannable,
  information-dense, calm. Status color carries meaning; never decoration.

## Audience

Developers and technical founders cloning the template to run their own
multi-agent workspace. They read code and a terminal; respect their fluency.

## Brand & design system — IDENTITY PRESERVATION WINS

The site already ships a committed design system — the **shadcn/ui "Vega" theme**
(`System_Config/html-template.html`). Do **not** reinvent the palette or swap
fonts. Polish strictly within these committed tokens:

- Tokens are **HSL** custom properties with a full dark-mode block
  (`prefers-color-scheme: dark`). Keep both themes correct.
- Accent: `hsl(221,83%,53%)` (blue). Ink `hsl(222,47%,11%)`, rules
  `hsl(214,32%,91%)`, surfaces white. Status: ok `142`, warn `38`, fail `0`.
- Type: **Inter** (sans) + a system mono stack. One family, multiple weights.
- Radius `0.5rem`; subtle shadow; 1px rules. Restrained, not drenched.

## Hard constraints (do not break)

- **Self-contained & portable.** All CSS inlined in each page. No external CSS,
  no build step, no JS framework, no network fonts. The repo is cloned and
  served as static files from `docs/`.
- **Accessibility is shipped, not optional.** Keep skip links, `aria-live` on the
  health report, semantic landmarks, visible focus rings, ≥4.5:1 body contrast,
  and a real `prefers-reduced-motion` path for every animation.
- **`file://` AND Pages must both work.** `health.html` loads `status.js` via a
  `<script>` tag, never `fetch()`. Keep it that way.
- **Don't regress structure the CLAUDE.md template mandates:** sticky header with
  wordmark + back/nav, `<main>` content, footer linking home + health.

## What "better" means here

Tighten hierarchy, rhythm, and motion; sharpen copy; make the health dashboard
even more scannable. Stay on-brand and on-system. No cream/sand backgrounds, no
card-everything, no gratuitous effects.
