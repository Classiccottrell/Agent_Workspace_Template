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
# 5. Optionally install the background automation. Default: No.
# ---------------------------------------------------------------------------
INSTALL_AUTOMATION="n"
if [ "$(uname -s)" = "Darwin" ]; then
  printf "Install background automation now (daily ingest + health check + weekly notes)? [y/N] "
  if [ -t 0 ]; then
    read -r REPLY || REPLY=""
  else
    REPLY=""
    echo "(non-interactive: skipping automation install)"
  fi
  case "$REPLY" in
    [yY]|[yY][eE][sS]) INSTALL_AUTOMATION="y" ;;
    *)                 INSTALL_AUTOMATION="n" ;;
  esac
fi

if [ "$INSTALL_AUTOMATION" = "y" ]; then
  echo
  echo "→ Installing launchd agents…"
  bash "$SYSCFG/install_daily_ingest.sh"
  bash "$SYSCFG/install_healthcheck.sh"
  bash "$SYSCFG/install_friday_process.sh"
  echo "→ Automation installed. Verify with: launchctl list | grep vaultbrain"
else
  echo "→ Skipping background automation."
  echo "    Install later, individually:"
  echo "      bash System_Config/install_daily_ingest.sh"
  echo "      bash System_Config/install_healthcheck.sh"
  echo "      bash System_Config/install_friday_process.sh"
fi

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
