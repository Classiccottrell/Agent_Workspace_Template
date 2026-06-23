#!/usr/bin/env bash
# install_monday_init.sh — activate the Monday weekly-note initializer LaunchAgent.
# Runs monday_init.sh at login/startup AND every Monday 08:00. Idempotent: renders
# the plist template, reinstalls, and reloads the agent; monday_init.sh itself skips
# if the week's note already exists. Manual kickoff (bash System_Config/monday_init.sh)
# still works exactly as before — this only ADDS the automatic trigger.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.mondayinit"
TMPL="$SYSCFG/mondayinit.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

echo "→ Creating log dir (must exist before launchd opens its redirect targets)…"
mkdir -p "$SYSCFG/logs" "$LAUNCHD_LOG_DIR" "$HOME/Library/LaunchAgents"

echo "→ Rendering $TMPL → $DEST_PLIST (label: $LABEL)"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__WORKSPACE_ROOT__|$WORKSPACE|g" \
    -e "s|__LOG_DIR__|$LAUNCHD_LOG_DIR|g" \
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
  echo "  (check with: launchctl list | grep mondayinit)"

cat <<NOTE

────────────────────────────────────────────────────────────────────────────
Scheduled at login/startup AND Mondays 08:00. Same prerequisite as the other
agents: Full Disk Access for /bin/bash (already granted if daily-ingest works).

Manual kickoff still works (and is unaffected by this agent):
   DRY_RUN=1 bash System_Config/monday_init.sh    # preview
   bash System_Config/monday_init.sh              # create this week's note now

Disable the automatic trigger later (manual kickoff keeps working):
   launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
