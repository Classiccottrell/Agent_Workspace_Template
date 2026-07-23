# Agentic Light — Orchestrator Context

Lighter sibling of the parent workspace: Obsidian second brain + dev pipeline
+ LLM Council decision engine + self-bootstrapping. No background automation.

## Build / Run

- `bash bootstrap.sh` — interactive, idempotent scaffold (mkdir tree, chmod scripts, provider detect).
- `bash bootstrap.sh --check` — read-only doctor (tools + provider + no-automation note).
- `bash pipeline/run.sh` — Task Input → coder → ESLint gate → Playwright gate → Human Gate → `gh pr create`.
- `bash skills/skills.sh list` — list available skills.
- `bash skills/llm-council/run_council.sh "<question>"` — run the 5-advisor council + chairman synthesis.
- `bash System_Config/healthcheck.sh` — layered PASS/WARN/FAIL report, self-heals docs via `gen_site.py`.
- `bash System_Config/new_agent.sh <name> "<scope>" [--write]` — scaffold a new `agents/<name>.md`.

## Directory Map

```
Agentic_Light/
├── CLAUDE.md
├── bootstrap.sh
├── .obsidian/{app,appearance,core-plugins,community-plugins,graph}.json
├── Projects/_TEMPLATE/{BRIEF.md,README.md,active/.gitkeep,archive/.gitkeep}
├── System_Config/
│   ├── config.sh · mcp.defaults.json · new_agent.sh · README.md · logs/.gitkeep
│   ├── monday_init.sh · friday_process.sh · daily_ingest.sh · run_agent.sh
│   ├── gen_site.py · healthcheck.sh
├── agents/
│   ├── architect.md · coder.md · creative-director.md · curator.md · eng-manager.md · qa.md · README.md
│   └── council/{contrarian,first-principles,expansionist,outsider,executor,chairman}.md
├── skills/
│   ├── skills.sh
│   └── llm-council/{SKILL.md, advisors.json, run_council.sh, templates/decision-report.md}
├── extensions/langflow/{export_flow.py, flows/agentic-light-roster.json, README.md}
├── microsite/{template.html, index.html, health.html, status.json, README.md}
├── brain/
│   ├── CLAUDE.md · README.md
│   ├── raw/README.md
│   ├── wiki/index.md
│   ├── weekly_logs/{Weekly_Note_Template.md, "2026 Master Note.md", 2026/2026-W30.md}
│   └── council_decisions/README.md
└── pipeline/
    ├── run.sh · README.md · logs/.gitkeep
    └── lib/{eslint_gate.sh, playwright_gate.sh, human_gate.sh, pr_create.sh}
```

## Terminal Constraints

- Bash-3.2-safe: no associative arrays, no `mapfile`, no `${var,,}` — use `tr` for case work.
- Every script is relocatable: `ROOT="$(cd "$(dirname "$0")" && pwd)"` (or `${BASH_SOURCE[0]}` when sourced) at the top. Never hardcode an absolute path.
- `set -euo pipefail` in every script unless a step must survive a non-zero exit (guard with `|| true`).

## The 4 Karpathy Agentic Coding Principles

1. **Think Before Coding** — state assumptions and surface trade-offs before editing.
2. **Simplicity First** — write the minimum code required, eliminate speculative abstractions.
3. **Surgical Changes** — touch strictly the requested code, no drive-by refactoring.
4. **Goal-Driven Execution** — define explicit success criteria, verify with tests.

## Agent Roster

| Agent | Scope |
|---|---|
| `architect` | Blueprints, schema, directory structure decisions |
| `coder` | Implementation |
| `creative-director` | Brand/visual/copy review |
| `curator` | `brain/` knowledge base curation |
| `eng-manager` | `Projects/` lifecycle, PR drafting |
| `qa` | Test coverage, regression checks |
| `council/contrarian` | LLM Council advisor — challenges the majority view |
| `council/first-principles` | LLM Council advisor — reasons from fundamentals |
| `council/expansionist` | LLM Council advisor — explores upside/opportunity |
| `council/outsider` | LLM Council advisor — non-domain-expert sanity check |
| `council/executor` | LLM Council advisor — feasibility/execution risk |
| `council/chairman` | Synthesizes anonymized advisor input into one decision report |

`archivist` and `rally` are **excluded from this roster by design** — Agentic
Light has no archival pipeline and no rally/broadcast agent; do not add them.

## `.obsidian/` Is Shipped

Unlike the parent workspace (which gitignores `.obsidian/`), Agentic Light
ships `app.json`, `appearance.json`, `core-plugins.json`,
`community-plugins.json`, `graph.json` directly. This is the only supported
KB strategy here (no VS Code/Foam alternative), so committing vault config
guarantees every clone opens with working core plugins and graph view with
zero setup. `workspace.json`/`workspace-mobile.json` (per-machine session
state) are intentionally omitted.
