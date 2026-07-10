# Improvements Backlog

Twenty independent cards: 1–10 close today's gaps, 11–20 future-proof the
template against change (model churn, spec drift, roster growth, tool lock-in).
Each card is **what · why · a fix prompt** you can paste into any capable model —
prompts are self-contained; run them from the workspace root. Items 1–4 unblocked
the public release and are done, as is 5; the rest can land in any order.
Status lines are appended to cards as they land — keep this file current.

## Today's gaps (1–10)

### 1. Cross-platform automation shim — ✅ DONE 2026-07-09
**Landed:** `SCHEDULER` detect + `install_cron_job`/`remove_cron_job` in `config.sh`; all 5 installers branch to cron on Linux, print manual guidance elsewhere; macOS path unchanged. Windows native scheduling still open (WSL works via cron).
**Why:** the whole `System_Config/` layer is macOS `launchd` — the single biggest blocker to "anyone can install."
> **Prompt:** "In `System_Config/`, the 5 `install_*.sh` scripts render `.plist.tmpl` files for macOS launchd. Add an OS branch: on Linux render an equivalent `cron` entry, on Windows print WSL/Task-Scheduler guidance. Keep macOS behavior byte-identical. Add a `SCHEDULER` detect in `config.sh`. Show me the diff for one installer (`install_daily_ingest.sh`) as the pattern before doing the rest."

### 2. Single-source orchestrator rules — ✅ DONE 2026-07-09
**Landed:** shared sections live in `System_Config/orchestrator-rules.md`; `sync_rules.sh` regenerates the `SHARED:*` marker regions in `CLAUDE.md` + `.agents/AGENTS.md`; `--check` exits 1 on drift (verified with a live drift test).
**Why:** `CLAUDE.md` and `.agents/AGENTS.md` are near-verbatim mirrors — every rule change must be edited twice and drifts (see docs/FAILURE_MODES.md F6).
> **Prompt:** "`CLAUDE.md` (Claude) and `.agents/AGENTS.md` (Gemini) duplicate the same orchestration rules. Extract the shared body into `System_Config/orchestrator-rules.md` and have both files include/reference it, or add a `make sync-rules` that regenerates both from the source. Do not change the actual rules. Prove the two outputs match."

### 3. Install doctor + clean uninstaller — ✅ DONE 2026-07-09
**Landed:** `./bootstrap.sh --check` (tools + job status + FDA reminder), `--uninstall` (confirm, bootout + plist/cron removal, data untouched), `--help`.
**Why:** there's no way to verify a healthy install or cleanly remove the launchd jobs.
> **Prompt:** "Add `./bootstrap.sh --check` (prints found/missing for `claude|gemini|gh|node|npx|python3`, launchd job status via `launchctl print`, FDA reminder) and `./bootstrap.sh --uninstall` (boots out all 5 launchd jobs and removes the plists, leaves data untouched). Reuse the existing bootout/bootstrap fallback pattern already in `System_Config/install_*.sh`. Non-destructive; confirm before removing."

### 4. Vault auto-commit snapshots — ✅ DONE 2026-07-09
**Landed:** `vault_snapshot.sh` + installer + plist (daily INGEST_HOUR+1:15). Vault-only commits, skips when the index is staged, push failure non-fatal. First snapshot committed same day.
**Why:** `Vault_Brain/` is auto-fed by ingest but never committed — a crash loses knowledge.
> **Prompt:** "Add `System_Config/vault_snapshot.sh` that runs `git add Vault_Brain && git commit -m 'chore(vault): snapshot' && git push` (skip if no changes), plus an installer `install_vault_snapshot.sh` scheduling it daily after ingest. Model it on the existing `install_daily_ingest.sh`. Guard against committing secrets or `.mcp.json`."

### 5. Secrets hygiene — ✅ DONE 2026-07-09
**Landed:** `.gitignore` covers `.mcp.json`/`*.key`/`.env*` (with `!.env.example`) / logs; `.env.example` documents the `~/.config/anthropic/key` path; audit found zero tracked secrets and a credential-free `.mcp.json`.
**Why:** `.mcp.json` and API keys risk being committed as the template gets shared publicly.
> **Prompt:** "Audit `.gitignore` and confirm `.mcp.json`, `*.key`, `.env`, `System_Config/logs/` are ignored. Add a `.env.example`, document the `~/.config/anthropic/key` path `daily_ingest.sh` reads, and add a bootstrap warning if `.mcp.json` contains a non-empty token. Show what's currently tracked that shouldn't be: `git ls-files | grep -Ei 'key|env|secret|token'`."

### 6. MCP server presets + picker — ✅ DONE 2026-07-09
**Landed:** `.mcp.json.example` ships filesystem/github/fetch presets under `_disabled_examples` (copy into `mcpServers` to enable, then allow-list in `.claude/settings.json`); bootstrap points at them on seed. No interactive picker — the presets + message cover it.
**Why:** `.mcp.json.example` is empty; users re-add the same servers per project.
> **Prompt:** "Populate `.mcp.json.example` with 3–5 common MCP servers (filesystem, github, etc.) disabled by default, and add a bootstrap prompt to enable a subset, writing to `.mcp.json`. Never overwrite an existing `.mcp.json`. Document in `README.md`."

### 7. Template self-tests (CI) — ✅ DONE 2026-07-09
**Landed:** `System_Config/test.sh` (bash -n + shellcheck errors + rules-drift + schema checks, PASS/FAIL summary) + `.github/workflows/ci.yml` running it on every push/PR. One shellcheck ERROR fixed (run_agent.sh shell directive); 54 style warnings inventoried, deliberately unfixed.
**Why:** nothing validates the scripts before a user clones.
> **Prompt:** "Add `shellcheck` over every `*.sh` in the repo root and `System_Config/`, plus `bash -n` syntax checks, wired as a `.github/workflows/ci.yml` GitHub Action and a local `System_Config/test.sh`. Fix any shellcheck errors it surfaces in the existing scripts. Start by listing the errors before fixing."

### 8. Upstream update mechanism — ⏳ OPEN (deliberately last)
**Note:** touches installed users' working trees — path-scope mistakes here can clobber data. Do this one attended, not via a lesser model, and dry-run first.
**Why:** an installed user can't pull template improvements without clobbering their `Projects/`/`Vault_Brain/` data.
> **Prompt:** "Design and add `./bootstrap.sh --update`: fetches the template's upstream, updates only system files (`System_Config/`, `.claude/agents/`, `.agents/skills/`, `CLAUDE.md`, `bootstrap.sh`) and never touches `Projects/`, `Final_Products/`, `Vault_Brain/`, `.mcp.json`. Use a git strategy (sparse checkout or path-scoped merge). Dry-run by default; show the file list before applying."

### 9. First-run onboarding — ✅ DONE 2026-07-09
**Landed:** root `WELCOME.md` (first 15 minutes: open, delegate, clip, ingest, check) + disposable sandbox `Projects/example/` (hello.sh + toy BRIEF). `Projects/example-project/` stays as the reference brief; bootstrap prints the WELCOME pointer.
**Why:** a fresh clone drops the user into a cold workspace with no guided start.
> **Prompt:** "Create a `WELCOME.md` shown after `./bootstrap.sh` completes (echo a pointer to it) that walks a new user through: open in Claude/Gemini, try one orchestrator command, add a first web clip, watch it ingest. Seed one tiny example under `Projects/example/` with a `BRIEF.md` demonstrating the eng-manager flow. Keep it deletable."

### 10. Ingest resilience & observability — ✅ DONE 2026-07-09
**Landed:** quota-wall detection (2 consecutive bad clips → loud log + stop, next scheduled run retries); summary line includes pending count; healthcheck Layer I "Ingest" surfaces pending/total in the status page.
**Why:** the ingest hits a provider quota wall (~5–6 clips/run) with no visible metrics; failures are quiet.
> **Prompt:** "In `System_Config/daily_ingest.sh` add exponential backoff + a clear log line on quota/budget exit (not a silent stop), and have `healthcheck.sh` surface per-source counts (clips pending, ingested, last-run status) into the status page it already writes. Don't change the one-clip-per-call design. Show the healthcheck diff."

## Future-proofing (11–20)

### 11. Central model registry — ✅ CLOSED (not needed) 2026-07-09
**Audit result:** zero hardcoded model IDs anywhere in the template scripts, plists, or agent files — the CLIs run without `--model` and use their configured defaults. Registry would be dead flexibility; reopen only if a script gains a `--model` flag.
**Why:** model IDs churn; scattered hardcodes make every bump a hunt.
> **Prompt:** "Grep the repo for hardcoded model identifiers (`claude-*`, `gemini-*`, `opus`, `sonnet`, `haiku`). Consolidate them into a single `System_Config/models.sh` (e.g. `MODEL_INGEST`, `MODEL_ORCHESTRATOR`) sourced by the scripts, so a model rename is a one-line change. List every occurrence before consolidating."

### 12. Template versioning + CHANGELOG — ✅ DONE 2026-07-09
**Landed:** `VERSION` (0.1.0), `CHANGELOG.md` (Keep-a-Changelog, Unreleased), bootstrap banner prints the version, convention documented in README.
**Why:** users and the `--update` mechanism (#8) need to know what version they have.
> **Prompt:** "Add a `VERSION` file (semver, start `0.1.0`) and a `CHANGELOG.md` (Keep-a-Changelog format) at the repo root. Have `bootstrap.sh` print the version on run. Document the release/bump convention in `README.md`. Don't invent history — start the changelog at Unreleased."

### 13. Vault schema versioning + migration path — ✅ DONE 2026-07-09
**Landed:** `Vault_Brain/.vault-schema` (v1), `migrate_vault.sh` (up-to-date no-op, empty migration case, newer-than error), convention in `Vault_Brain/README.md`.
**Why:** the wiki schema in `Vault_Brain/CLAUDE.md` will evolve; old vaults must upgrade without hand-editing.
> **Prompt:** "Add a `schema_version` marker to `Vault_Brain/` (e.g. a `.vault-schema` file) and a `System_Config/migrate_vault.sh` stub that reads current vs target version and no-ops when equal. Document the migration convention in `Vault_Brain/README.md`. Ship version 1 matching today's schema; no data changes."

### 14. Config schema validation on load — ✅ DONE 2026-07-09
**Landed:** `validate_config()` in config.sh (13 required vars, dir existence, hour/minute/provider ranges; returns, never exits) wired into all six installers. Verified both pass and fail paths.
**Why:** as `config.sh` grows, a typo silently breaks background jobs.
> **Prompt:** "Add a `validate_config()` function to `System_Config/config.sh` that asserts required vars are set and paths exist, called at the top of each `install_*.sh` and the ingest/process scripts. On failure print the offending var and exit non-zero. Keep it pure bash 3.2. Show one script wired as the pattern."

### 15. Agent-roster scaffolder — ✅ DONE 2026-07-09
**Landed:** `new_agent.sh <name> "<scope>"` renders both harness files from the coder pattern; dry-run default, `--write` to create, refuses overwrites, prints the .AGENT.MD registration reminder.
**Why:** every new agent must be added in TWO places (`.claude/agents/` + `.agents/skills/`) or the providers drift.
> **Prompt:** "Add `System_Config/new_agent.sh <name> <scope>` that scaffolds both `.claude/agents/<name>.md` and `.agents/skills/<name>/SKILL.md` from a shared template and reminds the user to register it in `.AGENT.MD`'s coordination matrix. Model the templates on the existing `coder` entries. Dry-run print before writing."

### 16. Skill index + versioning — ✅ DONE 2026-07-09
**Landed:** `## Skill Index` table in `.AGENT.MD` (all six skills, v1); `sync-skills.sh` warns non-fatally when a repo skill is missing from the index.
**Why:** skills will proliferate; without an index they're undiscoverable and unversioned.
> **Prompt:** "Add a skill index (extend `.AGENT.MD`) listing every skill with name, one-line purpose, location, and a version field. Add a `sync-skills.sh` check that flags skills missing from the index. Don't change skill behavior — just catalog them."

### 17. CLI dependency pinning + upstream-break detector — ✅ DONE 2026-07-09
**Landed:** `deps.sh` records tested versions; `--check`/`--check-deps` prints an informational drift line on mismatch. Never blocks.
**Why:** `gh`, Playwright, `agy`, `npx skills` all evolve; a breaking upstream change fails silently in a background job.
> **Prompt:** "Add a `System_Config/deps.sh` recording the tested version of each external CLI (`gh`, `node`, `playwright-cli`, `agy`/`gemini`, `claude`) and a `--check-deps` mode in `bootstrap.sh` that warns when the installed version differs from tested. Informational, never blocks. List current installed versions first."

### 18. Provider-agnostic invocation layer — ✅ DONE 2026-07-09
**Landed:** `System_Config/run_agent.sh` (sourced library, byte-equal flags + watchdog) now the single provider branch; `daily_ingest.sh` and `friday_process.sh` source it. Flag changes happen in one place.
**Why:** the claude-vs-gemini flag differences are copy-pasted across `daily_ingest.sh` and `friday_process.sh`; a new provider or flag change means editing every script.
> **Prompt:** "Extract the provider-branch `run_claude` function in `System_Config/daily_ingest.sh` and `friday_process.sh` into one shared `System_Config/run_agent.sh` that both source, so provider/flag logic lives in one place. Behavior must stay identical per provider. Diff both callers before and after."

### 19. Workspace export/import (anti-lock-in) — ✅ DONE 2026-07-09
**Landed:** `export_workspace.sh` (dated tar.gz, secrets/logs/git excluded) + `import_workspace.sh` (refuses non-empty targets). Round-trip diff verified empty.
**Why:** the whole value is a portable knowledge system; it should survive a move off this tool/machine as a plain archive.
> **Prompt:** "Add `System_Config/export_workspace.sh` that tars `Vault_Brain/`, `Projects/`, `Final_Products/`, and config (excluding secrets, logs, node_modules, .git) into a dated portable archive, plus a matching `import_workspace.sh`. Document in `README.md`. Verify a round-trip (export → fresh dir → import) preserves the vault."

### 20. Longitudinal observability — ✅ DONE 2026-07-09
**Landed:** `logs/metrics.tsv` (date, pending, ingested-total, jobs, wiki pages) appended each healthcheck run, header once, append-only; last snapshot surfaced in the status page via Layer I.
**Why:** `healthcheck.sh` shows only the current snapshot; trends (ingest volume, failure rate over weeks) are invisible.
> **Prompt:** "Have `healthcheck.sh` append a dated one-line metrics record (clips ingested, jobs healthy/failed, vault page count) to `System_Config/logs/metrics.tsv` on each run, and add a small section to the status page charting the last 30 records. Append-only; don't rewrite history. Show the healthcheck diff."
