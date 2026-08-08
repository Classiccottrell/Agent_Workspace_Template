#!/usr/bin/env bash
#
# bootstrap.sh — one-command setup for the Agent Workspace Template.
#
# Operates IN PLACE at the location you cloned to. It is idempotent and safe:
# it never deletes or overwrites your data. Re-run it any time.
#
#   ./bootstrap.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SYSCFG="$ROOT/System_Config"

# ---------------------------------------------------------------------------
# Argument handling — --check / --uninstall / --help run before normal setup.
# ---------------------------------------------------------------------------
SUFFIXES="dailyingest healthcheck fridayprocess mondayinit syncskills decisionssweep"

case "${1:-}" in
  --help)
    echo "Usage: ./bootstrap.sh [--check|--check-deps|--uninstall|--help]"
    echo "  (no args)    run the interactive setup"
    echo "  --check      read-only doctor: report tool + automation status"
    echo "  --check-deps alias for --check"
    echo "  --uninstall  remove background automation (launchd/cron); data is never touched"
    exit 0
    ;;
  --check|--check-deps)
    echo "=================================================="
    echo " Agent Workspace Template — check"
    echo "=================================================="
    echo
    # shellcheck source=/dev/null
    [ -f "$SYSCFG/deps.sh" ] && . "$SYSCFG/deps.sh" || true
    echo "→ Tools:"
    for t in agy gemini claude codex ollama gh node npx python3; do
      if p="$(command -v "$t" 2>/dev/null)"; then
        echo "  [ok] $t $p"
        if [ "$t" = "gh" ]; then
          if gh auth status >/dev/null 2>&1; then
            echo "       gh auth status: ok"
          else
            echo "       gh auth status: unauthenticated"
          fi
        fi
        installed_ver="$("$t" --version 2>/dev/null | head -1)" || installed_ver=""
        var_name="TESTED_$(echo "$t" | tr '[:lower:]' '[:upper:]')"
        eval "tested_ver=\"\${$var_name:-}\""
        if [ -n "$tested_ver" ] && [ -n "$installed_ver" ] && [ "$tested_ver" != "$installed_ver" ]; then
          echo "     tested: $tested_ver / installed: $installed_ver — untested combination (informational)"
        fi
      else
        echo "  [--] $t missing"
      fi
    done
    echo
    echo "→ Automation:"
    # shellcheck source=/dev/null
    source "$SYSCFG/config.sh"
    if [ "$SCHEDULER" = "launchd" ]; then
      for s in $SUFFIXES; do
        label="$LABEL_PREFIX.$s"
        if out="$(launchctl print "gui/$(id -u)/$label" 2>/dev/null)"; then
          state_line="$(echo "$out" | grep -m1 "state = " || true)"
          echo "  [ok] $label loaded (${state_line#*state = })"
        else
          echo "  [--] $label not loaded"
        fi
      done
    elif [ "$SCHEDULER" = "cron" ]; then
      cron_lines="$(crontab -l 2>/dev/null | grep 'agent-ws:' || true)"
      if [ -n "$cron_lines" ]; then
        echo "$cron_lines" | sed 's/^/  /'
      else
        echo "  none"
      fi
    else
      echo "  no scheduler on this platform"
    fi
    echo
    echo "[note] To run the background automation, grant Full Disk Access to /bin/bash — see System_Config/README.md."
    exit 0
    ;;
  --uninstall)
    # shellcheck source=/dev/null
    source "$SYSCFG/config.sh"
    echo "=================================================="
    echo " Agent Workspace Template — uninstall"
    echo "=================================================="
    echo
    echo "This will remove background automation only. Vault_Brain/, Projects/, and logs are never touched."
    echo
    if [ "$SCHEDULER" = "launchd" ]; then
      echo "The following launchd jobs will be removed:"
      for s in $SUFFIXES; do
        echo "  - $LABEL_PREFIX.$s  ($HOME/Library/LaunchAgents/$LABEL_PREFIX.$s.plist)"
      done
    elif [ "$SCHEDULER" = "cron" ]; then
      echo "The following cron entries will be removed:"
      crontab -l 2>/dev/null | grep 'agent-ws:' | sed 's/^/  /' || echo "  none"
    else
      echo "No scheduler automation is installed on this platform."
    fi
    echo
    if [ ! -t 0 ]; then
      echo "Non-interactive session — aborting without changes. Re-run interactively to confirm."
      exit 0
    fi
    printf "Remove background automation? [y/N]: "
    read -r UNINSTALL_REPLY || UNINSTALL_REPLY=""
    case "$UNINSTALL_REPLY" in
      [yY]*)
        if [ "$SCHEDULER" = "launchd" ]; then
          for s in $SUFFIXES; do
            label="$LABEL_PREFIX.$s"
            launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
            rm -f "$HOME/Library/LaunchAgents/$label.plist"
            echo "  removed $label"
          done
        elif [ "$SCHEDULER" = "cron" ]; then
          for s in $SUFFIXES; do
            # decisionssweep installs two cron entries (noon + evening), each under
            # its own marker — see install_decisions_sweep.sh.
            if [ "$s" = "decisionssweep" ]; then
              remove_cron_job "decisionssweep-noon"
              remove_cron_job "decisionssweep-evening"
              echo "  removed cron entries: decisionssweep-noon, decisionssweep-evening"
            else
              remove_cron_job "$s"
              echo "  removed cron entry: $s"
            fi
          done
        fi
        echo "→ Automation removed. Data (Vault_Brain/, Projects/, logs) untouched."
        ;;
      *)
        echo "→ Aborted. No changes made."
        ;;
    esac
    exit 0
    ;;
  --*)
    echo "Unknown flag: ${1:-}"
    echo "Usage: ./bootstrap.sh [--check|--uninstall|--help]"
    echo "  (no args)    run the interactive setup"
    echo "  --check      read-only doctor: report tool + automation status"
    echo "  --uninstall  remove background automation (launchd/cron); data is never touched"
    exit 1
    ;;
esac

echo "=================================================="
echo " Agent Workspace Template — bootstrap$([ -f "$ROOT/VERSION" ] && printf ' v%s' "$(cat "$ROOT/VERSION")")"
echo " Workspace: $ROOT"
echo "=================================================="
echo

# ---------------------------------------------------------------------------
# 1. Make scripts executable.
# ---------------------------------------------------------------------------
echo "→ Making scripts executable…"
chmod +x "$ROOT/bootstrap.sh"
if [ -d "$SYSCFG" ]; then
  for f in "$SYSCFG"/*.sh; do
    [ -e "$f" ] || continue
    chmod +x "$f"
  done
fi

# ---------------------------------------------------------------------------
# 2. Ensure the log directory exists (launchd opens its redirect targets here).
# ---------------------------------------------------------------------------
echo "→ Ensuring System_Config/logs exists…"
mkdir -p "$SYSCFG/logs"

# ---------------------------------------------------------------------------
# 3. Seed .mcp.json from the example if absent (never overwrite an existing one).
# ---------------------------------------------------------------------------
if [ ! -f "$ROOT/.mcp.json" ] && [ -f "$ROOT/.mcp.json.example" ]; then
  cp "$ROOT/.mcp.json.example" "$ROOT/.mcp.json"
  echo "→ Created .mcp.json from .mcp.json.example."
  echo "    Edit .mcp.json to add your MCP servers, then enable them in"
  echo "    .claude/settings.json under enabledMcpjsonServers."
  echo "    Disabled presets to copy from live under _disabled_examples in .mcp.json."
elif [ -f "$ROOT/.mcp.json" ]; then
  echo "→ .mcp.json already present — leaving it untouched."
fi
echo

# ---------------------------------------------------------------------------
# 4. Prerequisite check (informational — does not block).
# ---------------------------------------------------------------------------
echo "→ Checking prerequisites…"
# Agent CLI — this workspace is provider-agnostic. Prefer agy (Gemini/Antigravity),
# fall back to claude (Claude Code). Mirrors the resolution order in config.sh.
if command -v agy >/dev/null 2>&1; then
  echo "    [ok]   Gemini CLI (agy / Antigravity) found: $(command -v agy)"
elif command -v gemini >/dev/null 2>&1; then
  echo "    [ok]   Gemini CLI found: $(command -v gemini)"
elif command -v claude >/dev/null 2>&1; then
  echo "    [ok]   Claude Code CLI found: $(command -v claude)"
elif command -v codex >/dev/null 2>&1; then
  echo "    [ok]   Codex CLI found: $(command -v codex)"
else
  echo "    [warn] No agent CLI found on PATH (need 'agy', 'gemini', 'claude', or 'codex')."
  echo "           Gemini CLI:  https://github.com/google-gemini/gemini-cli"
  echo "           Claude Code: https://docs.claude.com/en/docs/claude-code"
fi
if command -v ollama >/dev/null 2>&1; then
  echo "    [ok]   Ollama found: $(command -v ollama)"
else
  echo "    [opt]  Ollama not found — required only when selected as an ingest target."
fi

case "$(uname -s)" in
  Darwin) echo "    [ok]   macOS detected — background automation (launchd) is available." ;;
  *)      echo "    [warn] Not macOS — the launchd automation will not install here;"
          echo "           the agents and the Vault_Brain wiki still work." ;;
esac

# Optional tooling — nothing below blocks the install.
if command -v gh >/dev/null 2>&1; then
  echo "    [ok]   GitHub CLI (gh) found: $(command -v gh)"
  if ! gh auth status >/dev/null 2>&1; then
    echo "           Not authenticated yet — run: gh auth login"
  fi
else
  echo "    [opt]  GitHub CLI (gh) not found — agents use it for commit/push/PR"
  echo "           without burning model tokens. Install: brew install gh"
fi
if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
  echo "    [ok]   node/npx found: $(node --version)"
else
  echo "    [opt]  node/npx not found — needed by skill sync (npx skills) and"
  echo "           Playwright. Install: brew install node"
fi
if command -v python3 >/dev/null 2>&1; then
  echo "    [ok]   python3 found: $(command -v python3)"
else
  echo "    [opt]  python3 not found — needed by the doc-currency hook and the"
  echo "           weekly site generator. Install: brew install python3"
fi

echo "    [note] To run the background automation, grant Full Disk Access to /bin/bash"
echo "           (System Settings → Privacy & Security → Full Disk Access; drag in"
echo "           /bin/bash via Finder ⌘⇧G → /bin). See System_Config/README.md."
echo

# ---------------------------------------------------------------------------
# 5. Scheduling choice — auto (launchd agents) vs manual (run by hand) vs skip.
# ---------------------------------------------------------------------------
SCHEDULE="skip"
if [ "$(uname -s)" = "Darwin" ]; then
  echo "Weekly-note + ingest automation — how do you want to run it?"
  echo "  [a] auto   — install launchd agents: daily ingest (07:00), health check,"
  echo "               Friday close-out (16:30), Monday note init (login + Mon 08:00),"
  echo "               skill sync (on npx install + hourly), decisions sweep (12:00 + 18:00)"
  echo "  [m] manual — no agents; you run the scripts by hand when you want"
  echo "  [s] skip   — decide later (default)"
  printf "Choose [a/m/s]: "
  if [ -t 0 ]; then
    read -r REPLY || REPLY=""
  else
    REPLY=""
    echo "(non-interactive: skipping — install later with the commands below)"
  fi
  case "$REPLY" in
    [aA]|[aA][uU][tT][oO])         SCHEDULE="auto" ;;
    [mM]|[mM][aA][nN][uU][aA][lL]) SCHEDULE="manual" ;;
    *)                             SCHEDULE="skip" ;;
  esac
fi

case "$SCHEDULE" in
  auto)
    echo
    echo "→ Installing launchd agents (auto scheduling)…"
    bash "$SYSCFG/install_daily_ingest.sh"
    bash "$SYSCFG/install_healthcheck.sh"
    bash "$SYSCFG/install_friday_process.sh"
    bash "$SYSCFG/install_monday_init.sh"
    bash "$SYSCFG/install_sync_skills.sh"
    bash "$SYSCFG/install_decisions_sweep.sh"
    echo "→ Automation installed. Verify with: launchctl list | grep vaultbrain"
    ;;
  manual)
    echo
    echo "→ Manual mode — no agents installed. Run the weekly scripts by hand:"
    echo "      bash System_Config/monday_init.sh      # start the week (DRY_RUN=1 to preview)"
    echo "      bash System_Config/friday_process.sh   # close out the week"
    echo "      bash System_Config/daily_ingest.sh     # ingest new clips"
    echo "      bash System_Config/decisions_sweep.sh  # sweep for undocumented decisions"
    echo "    Switch to auto anytime by running the install_*.sh scripts."
    ;;
  *)
    echo
    echo "→ Skipping scheduling for now. Install later — auto (all six agents):"
    echo "      bash System_Config/install_daily_ingest.sh"
    echo "      bash System_Config/install_healthcheck.sh"
    echo "      bash System_Config/install_friday_process.sh"
    echo "      bash System_Config/install_monday_init.sh"
    echo "      bash System_Config/install_sync_skills.sh"
    echo "      bash System_Config/install_decisions_sweep.sh"
    echo "    …or just run them by hand (manual): bash System_Config/monday_init.sh, etc."
    ;;
esac

# ---------------------------------------------------------------------------
# 5b. Knowledge Base strategy selection.
# ---------------------------------------------------------------------------
echo
KB_STRATEGY="obsidian"
echo "→ Knowledge Base strategy — how will you view and clip notes?"
echo "  [1] Obsidian + Obsidian Web Clipper  (default)"
echo "        Native wikilinks, graph view, and backlinks."
echo "        Obsidian Web Clipper saves web pages to Vault_Brain/sources/."
echo "        Guide: docs/kb-obsidian.md"
echo "  [2] VS Code + MarkSnip"
echo "        Foam extension for graph, backlinks, and wikilinks in VS Code."
echo "        MarkSnip browser extension clips web pages to Vault_Brain/sources/."
echo "        Guide: docs/kb-vscode.md"
printf "Choose [1/2, default 1]: "
if [ -t 0 ]; then
  read -r KB_REPLY || KB_REPLY=""
else
  KB_REPLY=""
  echo "(non-interactive: defaulting to Obsidian + Obsidian Web Clipper)"
fi
case "$KB_REPLY" in
  2) KB_STRATEGY="vscode" ;;
  *) KB_STRATEGY="obsidian" ;;
esac

# Write KB_STRATEGY into config.sh (sed -i requires a backup extension on macOS bash 3.2)
sed -i.bak "s/^KB_STRATEGY=.*/KB_STRATEGY=\"${KB_STRATEGY}\"/" "$SYSCFG/config.sh" && rm -f "$SYSCFG/config.sh.bak"

echo "    [ok]   KB_STRATEGY set to: $KB_STRATEGY"

if [ "$KB_STRATEGY" = "vscode" ]; then
  echo "    [ok]   Writing Vault_Brain/.vscode/extensions.json with recommended extensions…"
  mkdir -p "$ROOT/Vault_Brain/.vscode"
  cat > "$ROOT/Vault_Brain/.vscode/extensions.json" << 'VSCJSON'
{
  "recommendations": [
    "foam.foam-vscode",
    "bierner.github-markdown-preview",
    "CodeSmith.markdown-inline-editor-vscode",
    "foam.foam-vscode-paste-image",
    "Gruntfuggly.todo-tree"
  ]
}
VSCJSON
  echo "    [ok]   Open Vault_Brain/ in VS Code and install recommended extensions."
fi

# ---------------------------------------------------------------------------
# 5c. Note ingestion configuration (all defaults are safe — Enter to accept).
# ---------------------------------------------------------------------------
echo
echo "→ Note ingestion — the daily job that wikifies clips and notes into Vault_Brain."
if [ -t 0 ]; then
  printf "  Source folders inside Vault_Brain/, colon-separated [sources]: "
  read -r ING_SOURCES || ING_SOURCES=""
  echo "  Agent targets (ordered multi-select):"
  echo "    [ ] 1 Claude"
  echo "    [ ] 2 Gemini / Antigravity"
  echo "    [ ] 3 Codex"
  echo "    [ ] 4 Ollama"
  echo "    [ ] 0 Legacy auto (Gemini, then Claude)"
  printf "  Select in priority order, comma-separated [keep current; fresh = legacy auto]: "
  read -r ING_TARGET_CHOICES || ING_TARGET_CHOICES=""
  ING_TARGETS=""
  old_ifs="$IFS"; IFS=','
  for choice in $ING_TARGET_CHOICES; do
    case "$choice" in 0|auto) INGEST_TARGETS=""; INGEST_PROVIDER="auto"; target="" ;;
      1|claude) target=claude ;; 2|gemini|agy) target=gemini ;;
      3|codex) target=codex ;; 4|ollama) target=ollama ;; *) target="" ;;
    esac
    if [ -n "$target" ]; then
      if ! command -v "$target" >/dev/null 2>&1 && { [ "$target" != gemini ] || ! command -v agy >/dev/null 2>&1; }; then
        echo "    [warn] $target CLI is not installed; this target will be skipped at runtime."
      fi
      ING_TARGETS="${ING_TARGETS:+$ING_TARGETS:}$target"
    fi
  done
  IFS="$old_ifs"
  printf "  Optional models (claude, gemini, codex, ollama; blank keeps current; fresh = CLI default): "
  read -r ING_MODELS || ING_MODELS=""
  printf "  Daily run hour, 0-23 [7]: "
  read -r ING_HOUR || ING_HOUR=""
  printf "  Per-clip budget in USD, claude only [1.00]: "
  read -r ING_BUDGET || ING_BUDGET=""
else
  ING_SOURCES=""; ING_TARGETS=""; ING_MODELS=""; ING_HOUR=""; ING_BUDGET=""
  echo "  (non-interactive: keeping defaults — sources, auto, 07:00, \$1.00)"
fi
# Validate; anything odd falls back to the default already in config.sh.
case "$ING_HOUR" in [0-9]|1[0-9]|2[0-3]) ;; *) ING_HOUR="" ;; esac
case "$ING_BUDGET" in *[!0-9.]*|"") ING_BUDGET="" ;; esac
case "$ING_MODELS" in *[!A-Za-z0-9._:/,-]*) ING_MODELS="" ;; esac
[ -n "$ING_SOURCES" ]  && sed -i.bak "s|^INGEST_SOURCES=.*|INGEST_SOURCES=\"\${INGEST_SOURCES:-${ING_SOURCES}}\"|"   "$SYSCFG/config.sh"
[ -n "$ING_TARGETS" ]  && sed -i.bak "s|^INGEST_TARGETS=.*|INGEST_TARGETS=\"\${INGEST_TARGETS:-${ING_TARGETS}}\"|" "$SYSCFG/config.sh"
[ "${ING_TARGET_CHOICES:-}" = "0" ] && sed -i.bak "s|^INGEST_TARGETS=.*|INGEST_TARGETS=\"\${INGEST_TARGETS:-}\"|" "$SYSCFG/config.sh"
if [ -n "$ING_MODELS" ]; then
  old_ifs="$IFS"; IFS=','; set -- $ING_MODELS; IFS="$old_ifs"
  for pair in "CLAUDE_MODEL:${1:-}" "GEMINI_MODEL:${2:-}" "CODEX_MODEL:${3:-}" "OLLAMA_MODEL:${4:-}"; do
    key="${pair%%:*}"; value="${pair#*:}"
    [ -n "$value" ] && sed -i.bak "s|^${key}=.*|${key}=\"\${${key}:-${value}}\"|" "$SYSCFG/config.sh"
  done
fi
[ -n "$ING_HOUR" ]     && sed -i.bak "s|^INGEST_HOUR=.*|INGEST_HOUR=\"\${INGEST_HOUR:-${ING_HOUR}}\"|"                "$SYSCFG/config.sh"
[ -n "$ING_BUDGET" ]   && sed -i.bak "s|^INGEST_MAX_BUDGET=.*|INGEST_MAX_BUDGET=\"\${INGEST_MAX_BUDGET:-${ING_BUDGET}}\"|" "$SYSCFG/config.sh"
rm -f "$SYSCFG/config.sh.bak"
# Reload effective values so blank/invalid-only input reports retained config.
source "$SYSCFG/config.sh"
echo "    [ok]   Ingestion config: sources=${INGEST_SOURCES} targets=${INGEST_TARGETS:-legacy-auto} hour=${INGEST_HOUR} budget=\$${INGEST_MAX_BUDGET}"
if [ "$SCHEDULE" = "auto" ] && [ -n "$ING_HOUR" ]; then
  echo "    [note] Re-rendering the ingest schedule with your hour…"
  if bash "$SYSCFG/install_daily_ingest.sh" >/dev/null; then
    echo "    [ok]   Daily ingest rescheduled to ${ING_HOUR}:00."
  else
    echo "    [warn] Daily ingest was not rescheduled; finish CLI setup, then rerun its installer."
  fi
fi

# ---------------------------------------------------------------------------
# 5d. Notifications — local delivery is unconditional and the default; webhook
#     delivery (Slack, Google Chat) is additive and opt-in.
# ---------------------------------------------------------------------------
echo
echo "→ Notifications — how should scheduled jobs alert you when something needs attention?"
echo "  [1] Local only (macOS Notification Center)         (default)"
echo "  [2] Local + Google Chat webhook"
echo "  [3] Local + Slack webhook"
echo "  [4] Local + both webhooks"
if [ -t 0 ]; then
  printf "Choose [1-4, default 1]: "
  read -r NOTIFY_CHOICE || NOTIFY_CHOICE=""
else
  NOTIFY_CHOICE=""
  echo "(non-interactive: defaulting to local-only)"
fi
case "$NOTIFY_CHOICE" in
  2|3|4) : ;;
  *)     NOTIFY_CHOICE="1" ;;
esac

NOTIFY_GCHAT_URL=""; NOTIFY_SLACK_URL=""
if { [ "$NOTIFY_CHOICE" = "2" ] || [ "$NOTIFY_CHOICE" = "4" ]; } && [ -t 0 ]; then
  printf "  Google Chat webhook URL (blank to skip / keep current): "
  read -r NOTIFY_GCHAT_URL || NOTIFY_GCHAT_URL=""
fi
case "$NOTIFY_GCHAT_URL" in
  ""|https://*) : ;;
  *) echo "    [warn] Google Chat URL must start with https:// — skipping."; NOTIFY_GCHAT_URL="" ;;
esac
if { [ "$NOTIFY_CHOICE" = "3" ] || [ "$NOTIFY_CHOICE" = "4" ]; } && [ -t 0 ]; then
  printf "  Slack webhook URL (blank to skip / keep current): "
  read -r NOTIFY_SLACK_URL || NOTIFY_SLACK_URL=""
fi
case "$NOTIFY_SLACK_URL" in
  ""|https://*) : ;;
  *) echo "    [warn] Slack URL must start with https:// — skipping."; NOTIFY_SLACK_URL="" ;;
esac

NOTIFY_ENV="$SYSCFG/.notify.env"
if [ -n "$NOTIFY_GCHAT_URL" ] || [ -n "$NOTIFY_SLACK_URL" ]; then
  if [ ! -f "$NOTIFY_ENV" ]; then
    if [ -f "$SYSCFG/.notify.env.example" ]; then
      cp "$SYSCFG/.notify.env.example" "$NOTIFY_ENV"
    else
      : > "$NOTIFY_ENV"
    fi
    chmod 600 "$NOTIFY_ENV"
  fi
  # Idempotent replace-else-append per key. sed is unsafe here — a webhook URL's
  # query string contains '&', which sed's replacement text reads as "whole
  # match" — so filter the old line out, then append the new one instead.
  set_notify_key() {
    key="$1"; value="$2"
    [ -n "$value" ] || return 0
    tmp="$(mktemp)"
    grep -v "^${key}=" "$NOTIFY_ENV" > "$tmp" 2>/dev/null || true
    printf '%s="%s"\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$NOTIFY_ENV"
  }
  set_notify_key "GCHAT_WEBHOOK_URL" "$NOTIFY_GCHAT_URL"
  set_notify_key "SLACK_WEBHOOK_URL" "$NOTIFY_SLACK_URL"
  chmod 600 "$NOTIFY_ENV"
  echo "    [ok]   Webhook notification(s) saved to System_Config/.notify.env (mode 600)."
else
  echo "    [ok]   Notifications: local only (macOS Notification Center)."
fi

# ---------------------------------------------------------------------------
# 6. Remote Git repository (optional).
# ---------------------------------------------------------------------------
echo
echo "→ Remote Git repository (optional)"
echo "  Link this workspace to a remote repo to push/pull from another machine."

GIT_REMOTE=""
if git remote get-url origin >/dev/null 2>&1; then
  echo "    [ok]   Remote already configured: $(git remote get-url origin)"
elif [ -t 0 ]; then
  # gh path: create the repo for the user instead of asking for a URL.
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf "  Create a private GitHub repo for this workspace with gh? [y/N]: "
    read -r GH_REPLY || GH_REPLY=""
    case "$GH_REPLY" in
      [yY]*)
        if ! git rev-parse --git-dir >/dev/null 2>&1; then
          echo "    [warn] Not a git repo (ZIP download?) — run 'git init && git add -A && git commit -m init' first."
        else
          git branch -M main 2>/dev/null || true
          if gh repo create "$(basename "$ROOT")" --private --source . --remote origin --push; then
            echo "    [ok]   Repo created and pushed via gh."
          else
            echo "    [warn] gh repo create failed — add a remote manually later."
          fi
        fi
        ;;
      *) echo "    [skip] No remote configured. Later: gh repo create --private --source . --push" ;;
    esac
  else
    printf "  Enter remote URL (leave blank to skip): "
    read -r GIT_REMOTE || GIT_REMOTE=""
  fi
else
  echo "  (non-interactive: skipping — add manually: git remote add origin <url>)"
fi

if [ -n "$GIT_REMOTE" ]; then
  # Guarded: under `set -e` a failed push (no auth) or a ZIP download (no .git)
  # must not abort the rest of the setup.
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git remote add origin "$GIT_REMOTE" 2>/dev/null || git remote set-url origin "$GIT_REMOTE"
    git branch -M main 2>/dev/null || true
    if git push -u origin main; then
      echo "    [ok]   Remote set: $GIT_REMOTE"
    else
      echo "    [warn] push failed (auth?) — setup continues; push later with: git push -u origin main"
    fi
  else
    echo "    [warn] Not a git repo (ZIP download?) — run 'git init && git add -A && git commit -m init' first."
  fi
elif ! git remote get-url origin >/dev/null 2>&1; then
  echo "    [skip] No remote configured. Add later:"
  echo "           git remote add origin <url>   (or: gh repo create --private --source . --push)"
  echo "           git branch -M main && git push -u origin main"
fi

# NOTE: the doc-currency hook ships pre-wired in .claude/settings.json (it uses
# $CLAUDE_PROJECT_DIR, so it is relocatable) — no bootstrap wiring step needed.

# ---------------------------------------------------------------------------
# 7. Next steps.
# ---------------------------------------------------------------------------
echo
echo "=================================================="
echo " Done. Next steps:"
echo "=================================================="

if [ "$KB_STRATEGY" = "vscode" ]; then
  echo " 1. Open Vault_Brain/ in VS Code:"
  echo "      code Vault_Brain/"
  echo "    Install recommended extensions when prompted, then open the Foam graph:"
  echo "      ⌘⇧P → Foam: Show Graph"
  echo "    Full guide: docs/kb-vscode.md"
else
  echo " 1. Open the knowledge vault in Obsidian:"
  echo "      Open Vault_Brain/ (not the workspace root) as an Obsidian vault."
  echo "    Install the Obsidian Web Clipper browser extension."
  echo "    Import the bundled template: System_Config/obsidian-webclipper-template.json"
  echo "    Full guide: docs/kb-obsidian.md"
fi

echo " 2. Drop a clip or note into Vault_Brain/sources/ to feed the wiki."
echo " 3. Run the health check and open the dashboard:"
echo "      bash System_Config/healthcheck.sh"
echo "      open System_Config/status_page.html"
echo " 4. Start working from this folder: run 'agy'/'gemini' (Gemini/Antigravity) or 'claude' (Claude Code)."
echo "    Or run 'codex' for Codex. Ollama is supported as a headless ingest target, not an orchestrator."
echo
echo " First 15 minutes: open WELCOME.md — a guided walkthrough (first command,"
echo " first delegation, first clip ingested). Deletable when you're done."
echo
echo " Reference: README.md, .AGENT.MD, System_Config/README.md, Vault_Brain/README.md"
echo
