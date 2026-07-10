# Brutal UX

Design system + microsite + three product plans built on UX Brutalism: raw economic principles (efficiency, utility, scarcity) over traditional UX psychology. See `BRIEF.md` for scope and acceptance criteria.

## Layout

```
Brutal-UX/
├── BRIEF.md      ← scope, constraints, status
├── README.md     ← this file
├── docs/         ← three execution-ready business plans / PRDs
│   ├── netzero-prd.md       (NetZero — F.I.R.E. budget ledger)
│   ├── terminal-red-prd.md  (Terminal Red — SRE incident command)
│   └── starktext-prd.md     (StarkText — anti-platform publishing)
└── app/          ← Next.js microsite — INDEPENDENT git repo, ignored by workspace repo
```

## Run

```bash
cd app
npm run dev     # http://localhost:3000
npm run build   # production check
```

Routes: `/` (manifesto + component sandbox + ledger specimen), `/netzero`, `/terminal-red`, `/starktext` (working product demos).

## Notes

- `app/` was scaffolded with `npx shadcn@latest init --preset b1oVxvbG --template next` and has its own git history. The workspace repo ignores it (root `.gitignore`, nested-repos block).
- **Vega template exception:** this project intentionally does NOT use `System_Config/html-template.html`. The Brutal UX design system (pure #000/#FFF, 2px borders, radius 0, zero animation) is the deliverable itself; tokens live in `app/app/globals.css` under "BRUTAL UX ENFORCEMENT LAYER".
