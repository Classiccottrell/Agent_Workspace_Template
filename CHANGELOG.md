# Changelog

All notable changes to this template are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed (hardening audit, 2026-07-17)
- `friday_process.sh`: define `SYSCFG` — the microsite-regen step crashed every Friday run under `set -u`
- `healthcheck.sh`: memory-dir slug now matches Claude Code's real slugging (`_`/`.`/space → `-`), so Layer H checks the directory that actually exists
- Doc-currency hook ships pre-wired in `.claude/settings.json` (bootstrap wiring block removed; hook uses `$CLAUDE_PROJECT_DIR`)
- `bootstrap.sh`: git remote/push steps guarded — a ZIP download (no `.git`) or failed auth no longer aborts setup mid-way
- `run_agent.sh`: watchdog escalates TERM → KILL after 20s so a wedged CLI can't hang a scheduled job forever; `cd "$VAULT"` failure aborts the call
- `update_active_projects.sh`: exits 1 with an error if the `## Active Projects` heading is missing instead of silently doing nothing
- `healthcheck.sh`: agent-roster check now includes `qa`

### Added (hardening audit, 2026-07-17)
- `daily_ingest.sh`: concurrency lock (`logs/daily_ingest.lock`) — overlapping runs skip instead of racing the manifest and chmod source-locking
- `daily_ingest.sh`: poisoned-clip quarantine — 3 failed/no-op attempts park a clip in `<dir>/.failed.log`; healthcheck Layer I surfaces the count
- `healthcheck.sh` Layer E: warns when the `## Active Projects` table drifts from `Projects/` reality
- `test.sh`: `py_compile` on hook + `gen_site.py`, JSON validation of `settings.json` / `.mcp.json.example`

### Added
- CI self-tests: `System_Config/test.sh` + GitHub Actions workflow
- Vault schema versioning (`.vault-schema` + `migrate_vault.sh`)
- Agent scaffolder `new_agent.sh` (both harness formats, dry-run default)
- Skill Index in `.AGENT.MD` + sync-skills drift warning
- CLI version pinning (`deps.sh`) surfaced in `--check`
- Workspace export/import scripts (anti-lock-in)
- Ingest quota-wall detection + `metrics.tsv` history in healthcheck

- First-run onboarding: `WELCOME.md` + disposable `Projects/example/` sandbox
- MCP server presets in `.mcp.json.example` (`_disabled_examples`)
- `validate_config()` guard in all installers
- Shared `System_Config/run_agent.sh` provider-invocation library


- Configurable ingestion (`INGEST_*` vars in `System_Config/config.sh`) — sources, provider, hour, per-clip budget.
- `gh` and Playwright wiring for token-free git operations and web UI verification.
- Cross-platform automation: `SCHEDULER` detect in `config.sh` with a `cron` fallback for Linux alongside macOS `launchd`.
- `bootstrap.sh --check` (install doctor) and `--uninstall` (clean automation removal, data untouched).
- Single-source orchestrator rules — `System_Config/orchestrator-rules.md` + `sync_rules.sh` regenerate `CLAUDE.md`/`.agents/AGENTS.md`.
- Vault auto-commit snapshots via `System_Config/vault_snapshot.sh` and its installer.
- `docs/FAILURE_MODES.md` and `docs/IMPROVEMENTS.md`, plus the `/how-i-write` skill.
