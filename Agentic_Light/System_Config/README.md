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

## Scripts arriving in later batches

Documented here once Batch 2/3/5 land:

- `run_agent.sh`, `monday_init.sh`, `friday_process.sh`, `daily_ingest.sh` — Batch 2 (brain scaffolding + weekly automation).
- `healthcheck.sh`, `gen_site.py` — Batch 5 (microsite + healthcheck).
