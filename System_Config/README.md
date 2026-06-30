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
| `CLAUDE` | `command -v agy`, then `gemini`, then `claude`, else fallback | — |

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
| `config.sh` | Shared, relocatable configuration. Sourced first by every other script. |
| `daily_ingest.sh` | Ingest new `Vault_Brain/sources/*.md` clips into the wiki, one headless `agy -p` or `claude -p` call per clip. Content-hash dedup via `sources/.ingested.log` (`<sha256>\t<filename>`). |
| `dailyingest.plist.tmpl` | launchd agent template: runs ingest daily at 07:00 + at login. Rendered into `~/Library/LaunchAgents/` by the installer. |
| `install_daily_ingest.sh` | Render + install/reload the ingest agent (idempotent). |
| `friday_process.sh` | Friday 16:30 weekly close-out: Claude writes a 1–2 sentence summary + append-only wiki cross-refs, deterministic bash edits the Master Note row (backup + validate + rollback), and a `.<week>.fridayclose.snapshot.md` baseline is saved (used Monday to detect weekend edits). |
| `fridayprocess.plist.tmpl` | launchd agent template: runs the close-out Fridays at 16:30. |
| `install_friday_process.sh` | Render + install/reload the Friday agent (idempotent). |
| `healthcheck.sh` | Probe all architecture layers (A–H) + doc currency → `status_page.html` + `status.json` (here), publish `docs/status.js` + `docs/status.json` for `docs/health.html`, **and** push the snapshot to `origin/main` (via a detached worktree) so the live Pages dashboard auto-updates. Always exits 0; never reports green on a broken system. |
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

> **Generated at runtime, not shipped:** `healthcheck.sh` writes
> `status_page.html` and `status.json` into this directory each time it runs.
> They are not part of the template — run the health check to create them.
>
> **Published to the microsite:** the same run also writes `docs/status.js` (a
> `window.__STATUS__` assignment) and `docs/status.json`. `docs/health.html` reads
> `status.js` via a `<script>` tag — not `fetch` — so the dashboard renders from
> `file://` and on the published GitHub Pages site alike.
>
> **Auto-updates the live Pages site:** to keep the *published* dashboard fresh
> without manual commits, each run pushes the snapshot to `origin/main` (Pages'
> source). Because the job usually has a feature branch checked out, it publishes
> through a detached worktree pinned to `origin/main`
> (`~/Library/Caches/agent-workspace-health-publish`) — it never commits on or
> disturbs your working checkout. Best-effort: a git/auth failure is logged to
> `logs/healthcheck.log` and the run still exits 0.

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
DRY_RUN=1 bash System_Config/daily_ingest.sh        # detection only, no Claude call
bash    System_Config/daily_ingest.sh               # real run
tail -f System_Config/logs/daily_ingest.log

# Weekly Friday close-out
DRY_RUN=1 bash System_Config/friday_process.sh      # preview, no Claude call
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
- **Ingest safety:** shell denied, cwd confined to the vault, clip files locked
  read-only during a run, per-clip budget + wall-clock caps, create-or-append only.
- **Doc currency:** the health check's *Documentation Currency* section flags any
  README older than the files it documents. When you change a script or schema,
  update the governing README in the same task (see root `CLAUDE.md` →
  *Documentation Integrity*).

## Related docs

- `../README.md` — workspace overview / entry point
- `../.AGENT.MD` — full workspace map + agent coordination matrix
- `../Vault_Brain/README.md` — how the knowledge vault works
