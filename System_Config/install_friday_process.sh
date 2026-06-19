#!/usr/bin/env bash
# install_friday_process.sh — activate the Friday 19:00 weekly close-out LaunchAgent.
# Idempotent: renders the plist template, reinstalls, and reloads the agent. The
# launchd label and all paths are derived at runtime. (Full Disk Access for
# /bin/bash — the same grant the daily-ingest agent needs — also covers this one.)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.fridayprocess"
TMPL="$SYSCFG/fridayprocess.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

echo "→ Creating log dir (must exist before launchd opens its redirect targets)…"
mkdir -p "$SYSCFG/logs" "$HOME/Library/LaunchAgents"

echo "→ Rendering $TMPL → $DEST_PLIST (label: $LABEL)"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__WORKSPACE_ROOT__|$WORKSPACE|g" \
    "$TMPL" > "$DEST_PLIST"

echo "→ (Re)bootstrapping the LaunchAgent…"
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
  echo "  (check with: launchctl list | grep fridayprocess)"

cat <<NOTE

────────────────────────────────────────────────────────────────────────────
Scheduled for Fridays at 19:00. Same prerequisites as daily ingest:
  • Full Disk Access for /bin/bash (already granted if daily-ingest works)
  • Login keychain auth (or the optional ~/.config/anthropic/key file)

Test it now without waiting for Friday:
   DRY_RUN=1 bash System_Config/friday_process.sh    # preview, no Claude
   bash System_Config/friday_process.sh              # real run
   tail -f System_Config/logs/friday_process.log

Disable later:
   launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
