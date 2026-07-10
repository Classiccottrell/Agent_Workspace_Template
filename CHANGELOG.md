# Changelog

All notable changes to this template are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); this project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
