# agents/ — Agentic Light Roster

Each agent is a single self-contained file: `agents/<name>.md`
(frontmatter `name`/`description`/`tools`/`model: inherit` + body). No split
`.md` + `SKILL.md` pair like the parent workspace — Agentic Light keeps one
file per role. Scaffold new ones with
`bash System_Config/new_agent.sh <name> "<scope>" [--write]`.

## Base roster

| Agent | Scope | Hands off to |
|---|---|---|
| `architect` | Blueprints, schema, directory structure decisions | `coder` |
| `coder` | Implementation, builds, tests | `qa` (production PRs), `eng-manager` |
| `eng-manager` | `Agentic_Light/Projects/` lifecycle | `architect`, `coder`, `qa` |
| `qa` | Test coverage, regression checks against cloned repos | `eng-manager` |
| `curator` | `Agentic_Light/brain/` knowledge base curation | — (terminal) |
| `creative-director` | Brand/visual/copy review (e.g. `microsite/`) | — (terminal, opt-out of Caveman Protocol) |

`archivist` and `rally` are **excluded from this roster by design**. Agentic
Light has no archival pipeline and no rally/broadcast agent — do not add
them back in; if a future task seems to need one, treat that as a signal to
route the work through the existing roster or reconsider the task, not to
silently reintroduce a role the spec deliberately dropped.

## Council roster (`agents/council/`)

Advisor personas invoked only via the `llm-council` skill
(`skills/llm-council/run_council.sh`) — never dispatched directly. Read-only
(`tools: Read, Grep, Glob`) except the chairman, the only role permitted to
write.

| Agent | Lens | Hands off to |
|---|---|---|
| `council/contrarian` | Argues against the majority/obvious position | `council/chairman` |
| `council/first-principles` | Reasons from fundamentals, ignores convention | `council/chairman` |
| `council/expansionist` | Maximizes scope/ambition — "what if we went further" | `council/chairman` |
| `council/outsider` | Naive-user lens — flags jargon and hidden assumptions | `council/chairman` |
| `council/executor` | Feasibility/cost/timeline — "can this actually ship" | `council/chairman` |
| `council/chairman` | Synthesis-only — writes the final decision report | — (terminal) |

See `skills/llm-council/SKILL.md` for the full workflow (parallel advisor
pass → anonymize → peer review → chairman synthesis → write to
`brain/council_decisions/` → index in `brain/wiki/index.md`).
