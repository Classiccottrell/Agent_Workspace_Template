#!/usr/bin/env bash
# install_closed_pickup.sh — activate the Closed/ pickup LaunchAgent (idempotent).
# Scans Closed/ hourly (+ on Closed/ change) for new project subfolders not yet
# registered in INDEX.md and appends a placeholder row for archivist review.

set -euo pipefail
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
validate_config || { echo "aborting: invalid config" >&2; exit 1; }

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.closedpickup"
TMPL="$SYSCFG/closedpickup.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

# ── Non-macOS: launchd is unavailable — fall back per $SCHEDULER (config.sh) ──
if [[ "${SCHEDULER:-launchd}" != "launchd" ]]; then
  if [[ "$SCHEDULER" == "cron" ]]; then
    mkdir -p "$SYSCFG/logs"
    install_cron_job "closedpickup" "0 * * * *" "$SYSCFG/closed_pickup.sh"
  else
    echo "No supported scheduler on this OS (need launchd or cron)."
    echo "Run manually or schedule yourself: bash System_Config/closed_pickup.sh"
  fi
  exit 0
fi

echo "→ Creating log dirs…"
mkdir -p "$SYSCFG/logs" "$LAUNCHD_LOG_DIR" "$HOME/Library/LaunchAgents"

echo "→ Rendering $TMPL → $DEST_PLIST (label: $LABEL)"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__WORKSPACE_ROOT__|$WORKSPACE|g" \
    -e "s|__LOG_DIR__|$LAUNCHD_LOG_DIR|g" \
    -e "s|__HOME__|$HOME|g" \
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
  echo "  (check with: launchctl list | grep closedpickup)"

cat <<NOTE

────────────────────────────────────────────────────────────────────────────
Closed pickup agent installed. Fires on Closed/ folder change + hourly + at login.
  Scans: Closed/  →  appends unregistered rows to  Closed/INDEX.md

Manual run:   bash System_Config/closed_pickup.sh
Dry run:      DRY_RUN=1 bash System_Config/closed_pickup.sh
Logs:         System_Config/logs/closed-pickup.log
Disable:      launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
