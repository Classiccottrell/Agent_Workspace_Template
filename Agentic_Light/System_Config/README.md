# System_Config

Scripts and configuration for Agentic Light. **No launchd/cron — every
script here runs by hand; that's the only way it runs in Agentic Light.**

## Scripts (this batch)

- **`config.sh`** — shared, relocatable configuration. Source from every
  script (`source "$SCRIPT_DIR/config.sh"`). Derives `WORKSPACE`, `BRAIN`,
  `RAW`, `LOG_DIR` from its own location. Resolves the agent provider
  (`agy` → `gemini` → `claude`, env-overridable via `AGENT_TYPE`) and
  exports it. Provides `validate_config()` (never exits — returns 0/1).
- **`mcp.defaults.json`** — provider-agnostic MCP server template. Copy to
  `../.mcp.json` and populate `mcpServers`; `bootstrap.sh` does this
  automatically on first run if `.mcp.json` is absent.
- **`new_agent.sh`** — `new_agent.sh <name> "<scope>" [--write]`. Scaffolds
  `agents/<name>.md` with frontmatter (`name`/`description`/`tools`/`model`).
  Dry-run by default; refuses to overwrite an existing file.
- **`logs/`** — script output lands here. `.gitkeep` tracks the empty dir.

- **`run_agent.sh`** — sourced library (not standalone). Provides
  `run_agent "<prompt>"`: a thin wrapper around the resolved agent CLI
  (`$CLAUDE`/`$AGENT_TYPE` from `config.sh`) with a wall-clock watchdog
  (`MAX_SECONDS`, default 300s) and a Claude-only budget cap (`MAX_BUDGET`).
  cwd is `$BRAIN`; file tools only, Bash denied.
- **`monday_init.sh`** — weekly initializer. Creates
  `brain/weekly_logs/${YEAR}/${YEAR}-Www.md` from the template, creates
  `brain/raw/${YEAR}/Wnn label/`, and adds a row to
  `brain/weekly_logs/${YEAR} Master Note.md`'s Weekly Index (backup → edit
  → validate → rollback). Implements **Vacation Recovery**: if the most
  recently logged week is more than 7 days behind the current week, inserts
  exactly one synthetic catch-up row (`catch-up`, weeks-skipped count) before
  resuming normal weekly notes. Atomic `mkdir` lock; `DRY_RUN=1` preview.
- **`friday_process.sh`** — weekly close-out. Appends a close-out line to
  the week's `## Claude Sessions`, fills the Master Note row's Summary cell
  (backup → awk rewrite → validate → rollback). Atomic `mkdir` lock;
  `DRY_RUN=1` preview. No microsite regen and no GitHub Pages publish here.
- **`daily_ingest.sh`** — scans `brain/raw/YYYY/Wnn label/*.md` (exactly two
  levels deep; deeper nesting WARNs and is skipped) for new clips and
  ingests each with one `run_agent` call, wikifying it into `brain/wiki/`.
  Content-hash manifest (`brain/raw/.ingested.log`, sha256-keyed) for
  idempotent re-scans; quarantines a clip after 3 failed attempts
  (`brain/raw/.failed.log`). Atomic `mkdir` lock; `DRY_RUN=1` preview.

- **`gen_site.py`** — regenerates `microsite/index.html`'s
  `<!-- gen:agents-start/end -->` / `<!-- gen:skills-start/end -->` blocks and
  `<!-- gen:agent-count -->` / `<!-- gen:skills-count -->` counters from
  `agents/*.md`, `agents/council/*.md`, and `skills/*/SKILL.md` frontmatter.
  `--check` exits 1 if stale (used by `healthcheck.sh`); `--dry-run` prints
  the diff without writing. Stdlib-only Python 3.
- **`healthcheck.sh`** — layered PASS/WARN/FAIL check: directory layout,
  agent/council/skill roster frontmatter completeness, brain scaffolding
  (`wiki/index.md`, current weekly note, Master Note sentinel), council
  decision ↔ wiki index sync, pipeline log recency, and doc currency.
  Self-heals a stale `microsite/index.html` by invoking `gen_site.py` for
  real. Writes `microsite/status.json` + `microsite/status.js` (the payload
  `microsite/health.html` renders). Never `set -e`, always exits 0. No
  launchd/cron trigger and no GitHub Pages publish step — run it by hand.
