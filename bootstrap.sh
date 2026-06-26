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

echo "=================================================="
echo " Agent Workspace Template — bootstrap"
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
elif [ -f "$ROOT/.mcp.json" ]; then
  echo "→ .mcp.json already present — leaving it untouched."
fi
echo

# ---------------------------------------------------------------------------
# 4. Prerequisite check (informational — does not block).
# ---------------------------------------------------------------------------
echo "→ Checking prerequisites…"
if command -v claude >/dev/null 2>&1; then
  echo "    [ok]   Claude Code CLI found: $(command -v claude)"
else
  echo "    [warn] Claude Code CLI not found on PATH."
  echo "           Install it and log in: https://docs.claude.com/en/docs/claude-code"
fi

case "$(uname -s)" in
  Darwin) echo "    [ok]   macOS detected — background automation (launchd) is available." ;;
  *)      echo "    [warn] Not macOS — the launchd automation will not install here;"
          echo "           the agents and the Vault_Brain wiki still work." ;;
esac

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
  echo "               skill sync (on npx install + hourly)"
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
    echo "→ Automation installed. Verify with: launchctl list | grep vaultbrain"
    ;;
  manual)
    echo
    echo "→ Manual mode — no agents installed. Run the weekly scripts by hand:"
    echo "      bash System_Config/monday_init.sh      # start the week (DRY_RUN=1 to preview)"
    echo "      bash System_Config/friday_process.sh   # close out the week"
    echo "      bash System_Config/daily_ingest.sh     # ingest new clips"
    echo "    Switch to auto anytime by running the install_*.sh scripts."
    ;;
  *)
    echo
    echo "→ Skipping scheduling for now. Install later — auto (all five agents):"
    echo "      bash System_Config/install_daily_ingest.sh"
    echo "      bash System_Config/install_healthcheck.sh"
    echo "      bash System_Config/install_friday_process.sh"
    echo "      bash System_Config/install_monday_init.sh"
    echo "      bash System_Config/install_sync_skills.sh"
    echo "    …or just run them by hand (manual): bash System_Config/monday_init.sh, etc."
    ;;
esac

# ---------------------------------------------------------------------------
# 6. Next steps.
# ---------------------------------------------------------------------------
echo
echo "=================================================="
echo " Done. Next steps:"
echo "=================================================="
echo " 1. Open the knowledge vault in Obsidian:"
echo "      open the Vault_Brain/ folder (not the workspace root) as a vault."
echo " 2. Drop a clip or note into Vault_Brain/sources/ to feed the wiki."
echo " 3. Run the health check and open the dashboard:"
echo "      bash System_Config/healthcheck.sh"
echo "      open System_Config/status_page.html"
echo " 4. Start working: run 'claude' from this folder."
echo
echo " Reference: README.md, .AGENT.MD, System_Config/README.md, Vault_Brain/README.md"
echo
