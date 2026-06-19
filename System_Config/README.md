# System_Config — Automation Hub

Scheduled jobs and installers that run the workspace. Three launchd agents (clip
ingestion + weekly Friday close-out + health check) plus weekly note scripts. All
scripts target macOS `/bin/bash` **3.2** — no bash 4+ features (no associative
arrays).

## Relocatable by design

Every script sources `config.sh` first, which derives all paths and the launchd
label namespace from its own location and the environment — **nothing is
hardcoded**. Clone this workspace anywhere and the scripts just work.

| Variable | Derived from | Default |
|----------|--------------|---------|
| `WORKSPACE` | the parent of `System_Config/` (resolved at runtime) | — |
| `VAULT` / `SOURCES` / `LOG_DIR` | `$WORKSPACE` | — |
| `LABEL_PREFIX` | `$AGENT_WS_LABEL_PREFIX`, else `com.$USER.vaultbrain` | `com.<username>.vaultbrain` |
| `CLAUDE` | `command -v claude`, else `~/.local/bin/claude` | — |

Override the launchd namespace before installing if you want a custom label:

```bash
export AGENT_WS_LABEL_PREFIX="com.acme.vaultbrain"
bash System_Config/install_daily_ingest.sh
```

## Prerequisite (once)

**Full Disk Access for `/bin/bash`** — System Settings → Privacy & Security →
Full Disk Access. The `+` picker resists system binaries, so drag it in: Finder
→ ⌘⇧G → `/bin` → drag `bash` onto the list → toggle on. Without it, launchd
jobs that read your `~/Documents` workspace fail with `Operation not permitted`
(exit 126).

## Contents

| File | Purpose |
|------|---------|
| `config.sh` | Shared, relocatable configuration. Sourced first by every other script. |
| `daily_ingest.sh` | Ingest new `Vault_Brain/sources/*.md` clips into the wiki, one headless `claude -p` call per clip. Content-hash dedup via `sources/.ingested.log` (`<sha256>\t<filename>`). |
| `dailyingest.plist.tmpl` | launchd agent template: runs ingest daily at 07:00 + at login. Rendered into `~/Library/LaunchAgents/` by the installer. |
| `install_daily_ingest.sh` | Render + install/reload the ingest agent (idempotent). |
| `friday_process.sh` | Friday 19:00 weekly close-out: Claude writes a 1–2 sentence summary + append-only wiki cross-refs, then deterministic bash edits the Master Note row (backup + validate + rollback). |
| `fridayprocess.plist.tmpl` | launchd agent template: runs the close-out Fridays at 19:00. |
| `install_friday_process.sh` | Render + install/reload the Friday agent (idempotent). |
| `healthcheck.sh` | Probe all 5 architecture layers + doc currency → `status_page.html` + `status.json`. Always exits 0; never reports green on a broken system. |
| `healthcheck.plist.tmpl` | launchd agent template: runs the health check at login + every 4 hours. |
| `install_healthcheck.sh` | Render + install/reload the health-check agent (idempotent). |
| `monday_init.sh` | Create the current ISO-week note from the template (manual / `cron 0 6 * * 1`). |
| `friday_archive.sh` | Archive the week's note (manual / `cron 0 18 * * 5`). |
| `obsidian-webclipper-template.json` | Obsidian Web Clipper template → writes clips to the vault's `sources/` folder with frontmatter (filename via `{{title\|safe_name}}`). |
| `logs/` | Per-job logs (`daily_ingest.log`, `healthcheck.log`, launchd `.out`/`.err`). |

> **Generated at runtime, not shipped:** `healthcheck.sh` writes
> `status_page.html` and `status.json` into this directory each time it runs.
> They are not part of the template — run the health check to create them.

## Installed plist names

The installers render each `*.plist.tmpl` into
`~/Library/LaunchAgents/<LABEL>.plist`, where `<LABEL>` is built from
`$LABEL_PREFIX`:

- `com.<username>.vaultbrain.dailyingest.plist`
- `com.<username>.vaultbrain.fridayprocess.plist`
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

# Install / disable the scheduled agents
bash System_Config/install_daily_ingest.sh
bash System_Config/install_friday_process.sh
bash System_Config/install_healthcheck.sh
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.dailyingest
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.fridayprocess
launchctl bootout gui/$(id -u)/com.${USER}.vaultbrain.healthcheck

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
