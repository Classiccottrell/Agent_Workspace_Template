# Changelog

All notable changes to this template are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed (ingest reliability, 2026-07-20)
- `daily_ingest.sh`: auth failures (revoked/invalid API key) previously produced the identical "QUOTA/BUDGET WALL suspected" log line as a real provider quota wall — now classified separately ("AUTH FAILURE suspected") by grepping each failed clip's captured output for auth-error markers, so troubleshooting isn't misdirected
- `daily_ingest.sh`: `~/.config/anthropic/key` is read unconditionally even when it's known-stale; `INGEST_IGNORE_KEYFILE=1` (new `config.sh` var) now skips it and falls through to login-keychain auth
- `daily_ingest.sh`: `INGEST_MAX_CLIPS_PER_RUN` (already declared, documented as a safety cap) was never actually enforced — a run processed the entire backlog regardless; now stops after that many attempts per run, same pattern as the existing quota-wall stop, logged distinctly as "PER-RUN CLIP CAP reached"
- `monday_init.sh`: if something else creates the week's note before the scheduled 08:00 run (e.g. an ingest agent's own "ensure the weekly note exists" fallback), the script used to see the file, log "skipping," and exit — silently dropping the Master Note index row and the prior week's carry-forward items forever. Now backfills both idempotently instead of skipping outright (verified: running it twice produces no duplicate carry-forward section or Master Note row)
- `monday_init.sh`: the week's `Raw_Notes` folder is created every Monday but was never added to `INGEST_SOURCES` — new weeks' clips were invisible to ingest (non-recursive scan) until someone noticed a log WARN and manually edited `config.sh`. Now auto-registers the new folder path in `config.sh` idempotently right after creating it

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
