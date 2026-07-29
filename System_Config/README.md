# System_Config — Automation Hub

Scheduled jobs and installers that run the workspace. Five launchd agents (clip
ingestion, Friday close-out, Monday note init, health check, skill sync) plus their scripts. All
scripts target macOS `/bin/bash` **3.2** — no bash 4+ features (no associative
arrays). Every scheduled script also runs by hand — the LaunchAgents only ADD the
automatic trigger; manual kickoff always works.

## Relocatable by design

Every script sources `config.sh` first, which derives all paths and the launchd
label namespace from its own location and the environment — **nothing is
hardcoded**. Clone this workspace anywhere and the scripts just work.

| Variable | Derived from | Default |
|----------|--------------|---------|
| `WORKSPACE` | the parent of `System_Config/` (resolved at runtime) | — |
| `VAULT` / `SOURCES` / `LOG_DIR` | `$WORKSPACE` | — |
| `LABEL_PREFIX` | `$AGENT_WS_LABEL_PREFIX`, else `com.$USER.vaultbrain` | `com.<username>.vaultbrain` |
| `CLAUDE` | Legacy binary variable; resolved from `INGEST_TARGETS`, or `agy` → `gemini` → `claude` in legacy mode | — |

Override the launchd namespace before installing if you want a custom label:

```bash
export AGENT_WS_LABEL_PREFIX="com.acme.vaultbrain"
bash System_Config/install_daily_ingest.sh
```

## Prerequisites (once)

**1. Full Disk Access for `/bin/bash`** — System Settings → Privacy & Security →
Full Disk Access. The `+` picker resists system binaries, so drag it in: Finder
→ ⌘⇧G → `/bin` → drag `bash` onto the list → toggle on. Without it, the scheduled
scripts can't read your `~/Documents` workspace.

**2. launchd log redirects live OUTSIDE the workspace.** Each agent's
`StandardOutPath`/`StandardErrorPath` resolve to `~/Library/Logs/$LABEL_PREFIX/`
(via `LAUNCHD_LOG_DIR` in `config.sh`), not the workspace — and this matters if you
clone into `~/Documents`. launchd opens those redirect files *itself, before*
exec'ing `/bin/bash`, and that open is **not** covered by bash's Full Disk Access, so
a redirect inside `~/Documents` makes the job die at spawn with `EX_CONFIG` (exit 78)
and **no output**, before the script runs. The scripts' own logs still live in
`System_Config/logs/` (written by bash, which has FDA).

## Contents

| File | Purpose |
|------|---------|
| `config.sh` | Shared, relocatable configuration. Sourced first by every other script. Holds the `INGEST_*` ingestion settings (see table below) and the `SCHEDULER` detect (launchd on macOS, cron on Linux, none elsewhere) with `install_cron_job`/`remove_cron_job` helpers the installers use off-Mac. |
| `orchestrator-rules.md` | **Single source** for rule sections shared by `AGENTS.md`, `CLAUDE.md`, and `.agents/AGENTS.md`. Edit here, then run `sync_rules.sh`. |
| `sync_rules.sh` | Regenerate the `SHARED:*` marker regions in `AGENTS.md`, `CLAUDE.md`, and `.agents/AGENTS.md` from `orchestrator-rules.md`. `--check` exits 1 on drift. |
| `run_agent.sh` | Sourced library: `run_agent <prompt>` — the single provider case (Claude, Gemini/Antigravity, Codex, Ollama flags + watchdog) shared by `daily_ingest.sh` and `friday_process.sh`. Watchdog sends TERM, then KILL 20s later (a wedged CLI can't hang the job). |
| `dispatch_tasks.sh` | Sourced bounded dispatcher. Input rows are `id<TAB>colon:scopes<TAB>command`; the bound must be a positive integer. Duplicate IDs or exact duplicate scope tokens fail before execution. Scope matching is literal, not path-aware. Commands execute through `bash -c`, so task files are trusted orchestrator input, not an untrusted-input boundary. |
| `deps.sh` | Recorded tested versions of the external CLIs; `./bootstrap.sh --check` prints an informational drift line when installed versions differ. |
| `test.sh` | Template self-test: `bash -n` + `shellcheck --severity=error` over every script, rules-drift check, schema check, `py_compile` on the Python (hook + `gen_site.py`), and JSON validation of `.claude/settings.json` / `.mcp.json.example`. Run locally anytime; CI runs it on every push (`.github/workflows/ci.yml`). |
| `migrate_vault.sh` | Vault schema migration runner (`Vault_Brain/.vault-schema` marker, TARGET_SCHEMA constant). No-ops when current; errors if the vault is newer than the template. |
| `new_agent.sh` | Scaffold a new agent in BOTH harness formats (`.claude/agents/` + `.agents/skills/`). Dry-run by default; `--write` creates. Register in `.AGENT.MD` afterwards. |
| `export_workspace.sh` / `import_workspace.sh` | Portable tar.gz of the vault + projects + agent configs (secrets/logs/git excluded); import refuses non-empty targets. Anti-lock-in escape hatch. |
| `vault_snapshot.sh` | Daily git snapshot of `Vault_Brain/` only (skips if the index has staged changes; push failure is non-fatal). |
| `vaultsnapshot.plist.tmpl` | launchd agent template: snapshot daily one hour after ingest (INGEST_HOUR+1, :15). |
| `install_vault_snapshot.sh` | Render + install/reload the snapshot agent (idempotent). |
| `daily_ingest.sh` | Ingest new `.md` notes from each dir in `INGEST_SOURCES`, one headless call per note. Verified successes checkpoint atomically. A rate/quota failure advances and saves the next provider; that failed note is not replayed in-run and retries on the saved provider next run. Auth and generic failures never hand off. State applies only while the configured target order matches. Shared writes keep ingest serialized behind `logs/daily_ingest.lock`. Three failures/no-ops quarantine a clip in `<dir>/.failed.log`. |
| `dailyingest.plist.tmpl` | launchd agent template: runs ingest daily at `INGEST_HOUR:INGEST_MINUTE` (default 07:00) + at login. Rendered into `~/Library/LaunchAgents/` by the installer. |
| `install_daily_ingest.sh` | Render + install/reload the ingest agent (idempotent). |
| `friday_process.sh` | Friday 16:30 weekly close-out: the configured agent writes a 1–2 sentence summary + append-only wiki cross-refs, deterministic bash edits the Master Note row (backup + validate + rollback), and a `.<week>.fridayclose.snapshot.md` baseline is saved (used Monday to detect weekend edits). |
| `fridayprocess.plist.tmpl` | launchd agent template: runs the close-out Fridays at 16:30. |
| `install_friday_process.sh` | Render + install/reload the Friday agent (idempotent). |
| `healthcheck.sh` | Probe all architecture layers (A–I) + doc currency → `status_page.html` + `status.json` (here), publish `docs/status.js` + `docs/status.json` for `docs/health.html`, **and** push the snapshot to `origin/main` (via a detached worktree) so the live Pages dashboard auto-updates. Layer E also warns when the `## Active Projects` table drifts from `Projects/`; Layer I surfaces pending + quarantined clips. Always exits 0; never reports green on a broken system. |
| `healthcheck.plist.tmpl` | launchd agent template: runs the health check at login + every 4 hours. |
| `install_healthcheck.sh` | Render + install/reload the health-check agent (idempotent). |
| `monday_init.sh` | Create the current ISO-week note from the template. Carries open tasks forward **grouped under their `#### Project` header** (with sub-bullets), and **merges weekend edits** to last week's note into the new one. Runs at login + Mon 08:00 via launchd, or by hand. |
| `mondayinit.plist.tmpl` | launchd agent template: runs `monday_init.sh` at login/startup + Mondays 08:00. |
| `install_monday_init.sh` | Render + install/reload the Monday agent (idempotent). |
| `sync-skills.sh` | Sync skills installed via `npx skills add -g` from `~/.agents/skills/` into `~/.claude/skills/` (Claude Code's actual read path), then flag any unindexed skills in `master-orchestrator`. |
| `syncskills.plist.tmpl` | launchd agent template: fires via WatchPaths on `~/.agents/skills` + hourly + at login. Rendered into `~/Library/LaunchAgents/` by the installer. |
| `install_sync_skills.sh` | Render + install/reload the skill-sync agent (idempotent). |
| `friday_archive.sh` | Archive the week's note (manual / `cron 0 18 * * 5`). |
| `obsidian-webclipper-template.json` | Obsidian Web Clipper template → writes clips to the vault's `sources/` folder with frontmatter (filename via `{{title\|safe_name}}`). |
| `logs/` | Per-job **script** logs (`daily_ingest.log`, `healthcheck.log`, …) in the workspace. The launchd `.out`/`.err` redirects live in `~/Library/Logs/$LABEL_PREFIX/` (see Prerequisites). |

### Ingestion configuration (`config.sh`)

Set by `bootstrap.sh` during setup; edit `config.sh` anytime (re-run
`install_daily_ingest.sh` after changing the schedule so the plist re-renders).
All are env-overridable per run.

| Var | Default | Meaning |
|-----|---------|---------|
| `INGEST_SOURCES` | `sources:Raw_Notes` | Colon-separated dirs (relative to `Vault_Brain/`) scanned for new `.md` notes. Each keeps its own `.ingested.log`. |
| `INGEST_PROVIDER` | `auto` | `auto` (PATH detection: agy → gemini → claude), or force `claude` / `gemini`. |
| `INGEST_TARGETS` | empty | Optional ordered colon list: `claude:gemini:codex:ollama`. Empty keeps legacy `INGEST_PROVIDER` behavior. Gemini resolves `agy` before `gemini`. An explicit list with no installed target fails closed. |
| `CLAUDE_MODEL` / `GEMINI_MODEL` / `CODEX_MODEL` / `OLLAMA_MODEL` | empty | Optional target-specific override; empty defers to the CLI default. Ollama uses the first locally installed model or exits with an actionable error when none exists. |
| `INGEST_HOUR` / `INGEST_MINUTE` | `7` / `0` | Daily launchd schedule, rendered into the plist on install. |
| `INGEST_MAX_BUDGET` | `1.00` | Per-clip USD ceiling — claude only (gemini has no cost flag). |
| `INGEST_MAX_SECONDS` | `900` | Per-call watchdog for all four providers; TERM then KILL 20 seconds later. |
| `INGEST_MAX_CLIPS_PER_RUN` | `10` | Attempt cap for each scheduled run; remaining notes carry forward. |

> **Generated at runtime, not shipped:** `healthcheck.sh` writes
> `status_page.html` and `status.json` into this directory each time it runs.
> They are not part of the template — run the health check to create them.
>
> **Auto-updates the live Pages site (no working-tree churn):** the dashboard is
> published as `docs/status.js` (a `window.__STATUS__` assignment) + `docs/status.json`,
> which `docs/health.html` reads via a `<script>` tag (not `fetch`). To keep the
> *published* dashboard fresh without manual commits, each run writes + commits those
> two files **only inside a detached worktree pinned to `origin/main`** (Pages' source)
> at `~/Library/Caches/agent-workspace-health-publish`, then pushes. The job's own
> checkout is never written to — so it no longer leaves `docs/status.*` perpetually
> dirty. Best-effort: a git/auth failure is logged to `logs/healthcheck.log` and the
> run still exits 0. For a fresh **local** view, open `status_page.html` here.

## Installed plist names

The installers render each `*.plist.tmpl` into
`~/Library/LaunchAgents/<LABEL>.plist`, where `<LABEL>` is built from
`$LABEL_PREFIX`:

- `com.<username>.vaultbrain.dailyingest.plist`
- `com.<username>.vaultbrain.fridayprocess.plist`
- `com.<username>.vaultbrain.mondayinit.plist`
- `com.<username>.vaultbrain.healthcheck.plist`

(`<username>` defaults to your `$USER`; override with `$AGENT_WS_LABEL_PREFIX`.)

## Common commands

All commands are relative to the workspace root.

```bash
# Health check — open the dashboard / run on demand
open    System_Config/status_page.html
bash    System_Config/healthcheck.sh

# Clip ingestion
DRY_RUN=1 bash System_Config/daily_ingest.sh        # detection only, no agent call
bash    System_Config/daily_ingest.sh               # real run
tail -f System_Config/logs/daily_ingest.log

# Weekly Friday close-out
DRY_RUN=1 bash System_Config/friday_process.sh      # preview, no agent call
bash    System_Config/friday_process.sh             # real run

# Weekly Monday init — manual kickoff (works regardless of the LaunchAgent)
DRY_RUN=1 bash System_Config/monday_init.sh         # preview this week's note
bash    System_Config/monday_init.sh                # create this week's note now

# Install / disable the scheduled agents
bash System_Config/install_daily_ingest.sh
bash System_Config/install_friday_process.sh
bash System_Config/install_monday_init.sh
bash System_Config/install_healthcheck.sh
bash System_Config/install_sync_skills.sh
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.dailyingest
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.fridayprocess
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.mondayinit
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.healthcheck
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.syncskills

# Skill sync
bash    System_Config/sync-skills.sh        # manual sync + re-index
tail -f System_Config/logs/sync-skills.log
launchctl bootout gui/$(id -u)/$LABEL_PREFIX.syncskills  # disable

# Verify a scheduled agent (col 2 = last exit status; 0 = healthy)
launchctl list | grep vaultbrain
```

## Conventions

- **Auth:** headless `claude` uses the login keychain (unlocked while logged in).
  Optional fallback for detached runs: `~/.config/anthropic/key` (mode 0600).
- **Provider controls:** Claude gets an allow-list, denied shell/network/task tools,
  edit permission mode, and the USD cap. Codex uses `workspace-write` sandbox.
  Gemini uses its sandbox plus `--dangerously-skip-permissions`; Ollama has no
  equivalent tool sandbox or USD cap. All run from the vault and share the watchdog.
- **Ingest safety:** source notes are locked read-only during a run; verified
  success is required before the manifest checkpoint. Provider output still writes
  wiki files, so keep backups and do not treat Ollama or prompt constraints as a
  security boundary.
- **Doc currency:** the health check's *Documentation Currency* section flags any
  README older than the files it documents. When you change a script or schema,
  update the governing README in the same task (see root `CLAUDE.md` →
  *Documentation Integrity*).

## Related docs

- `../README.md` — workspace overview / entry point
- `../.AGENT.MD` — full workspace map + agent coordination matrix
- `../Vault_Brain/README.md` — how the knowledge vault works
