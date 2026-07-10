#!/usr/bin/env bash
# install_healthcheck.sh — activate the workspace health-check LaunchAgent.
# Safe to re-run (idempotent): renders the plist template, reinstalls, and
# reloads the agent. The launchd label and all paths are derived at runtime.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
validate_config || { echo "aborting: invalid config" >&2; exit 1; }

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.healthcheck"
TMPL="$SYSCFG/healthcheck.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

# ── Non-macOS: launchd is unavailable — fall back per $SCHEDULER (config.sh) ──
if [[ "${SCHEDULER:-launchd}" != "launchd" ]]; then
  if [[ "$SCHEDULER" == "cron" ]]; then
    mkdir -p "$SYSCFG/logs"
    install_cron_job "healthcheck" "0 */4 * * *" "$SYSCFG/healthcheck.sh"
  else
    echo "No supported scheduler on this OS (need launchd or cron)."
    echo "Run manually or schedule yourself: bash System_Config/healthcheck.sh"
  fi
  exit 0
fi

echo "→ Creating log dir (must exist before launchd opens its redirect targets)…"
mkdir -p "$SYSCFG/logs" "$LAUNCHD_LOG_DIR" "$HOME/Library/LaunchAgents"

echo "→ Rendering $TMPL → $DEST_PLIST (label: $LABEL)"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__WORKSPACE_ROOT__|$WORKSPACE|g" \
    -e "s|__LOG_DIR__|$LAUNCHD_LOG_DIR|g" \
    "$TMPL" > "$DEST_PLIST"

echo "→ (Re)bootstrapping the LaunchAgent into your GUI session…"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
if launchctl bootstrap "gui/$UID_NUM" "$DEST_PLIST" 2>/dev/null; then
  echo "  bootstrapped via launchctl bootstrap."
else
  launchctl unload "$DEST_PLIST" 2>/dev/null || true
  launchctl load -w "$DEST_PLIST"
  echo "  loaded via legacy launchctl load -w."
fi

echo "→ Verifying registration:"
launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | grep -E "state|path" || \
  echo "  (launchctl print unavailable — check with: launchctl list | grep healthcheck)"

cat <<NOTE

────────────────────────────────────────────────────────────────────────────
Same prerequisite as daily ingest: FULL DISK ACCESS for /bin/bash (already
granted if daily_ingest runs). The health check is read-only and writes only
System_Config/status_page.html + status.json + logs/healthcheck.log.

View the page:    open System_Config/status_page.html
Run it now:       bash System_Config/healthcheck.sh
Disable later:    launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
