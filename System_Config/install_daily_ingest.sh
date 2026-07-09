#!/usr/bin/env bash
# install_daily_ingest.sh — activate the Vault_Brain daily ingestion LaunchAgent.
# Safe to re-run (idempotent): it renders the plist template, reinstalls, and
# reloads the agent. The launchd label and all paths are derived at runtime, so
# this works wherever the workspace is cloned.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.dailyingest"
TMPL="$SYSCFG/dailyingest.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

echo "→ Creating log dir (must exist before launchd opens its redirect targets)…"
mkdir -p "$SYSCFG/logs" "$LAUNCHD_LOG_DIR" "$HOME/Library/LaunchAgents"

echo "→ Rendering $TMPL → $DEST_PLIST (label: $LABEL, schedule: ${INGEST_HOUR}:$(printf '%02d' "$INGEST_MINUTE"))"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__WORKSPACE_ROOT__|$WORKSPACE|g" \
    -e "s|__LOG_DIR__|$LAUNCHD_LOG_DIR|g" \
    -e "s|__INGEST_HOUR__|$INGEST_HOUR|g" \
    -e "s|__INGEST_MINUTE__|$INGEST_MINUTE|g" \
    "$TMPL" > "$DEST_PLIST"

echo "→ (Re)bootstrapping the LaunchAgent into your GUI session…"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
if launchctl bootstrap "gui/$UID_NUM" "$DEST_PLIST" 2>/dev/null; then
  echo "  bootstrapped via launchctl bootstrap."
else
  # Legacy fallback for older macOS.
  launchctl unload "$DEST_PLIST" 2>/dev/null || true
  launchctl load -w "$DEST_PLIST"
  echo "  loaded via legacy launchctl load -w."
fi

echo "→ Verifying registration:"
launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null | grep -E "state|path" || \
  echo "  (launchctl print unavailable — check with: launchctl list | grep vaultbrain)"

cat <<NOTE

────────────────────────────────────────────────────────────────────────────
ONE PREREQUISITE the scheduled run needs (it cannot grant this itself):

  FULL DISK ACCESS for /bin/bash — the only binary that needs it.
  The Full Disk Access "+" picker resists system binaries, so DRAG IT IN:
    System Settings → Privacy & Security → Full Disk Access  (leave open)
    Finder → ⌘⇧G → /bin → drag the \`bash\` file onto the list → toggle on.

AUTH — usually nothing to do. Headless \`claude\` uses your login keychain,
  which is unlocked while you're logged in (when this agent runs). Optional
  fallback for fully-detached runs:
    mkdir -p ~/.config/anthropic
    printf '%s' 'sk-ant-...' > ~/.config/anthropic/key && chmod 600 ~/.config/anthropic/key
  daily_ingest.sh uses it automatically if present.

Test it now without waiting for 07:00:
   DRY_RUN=1 bash System_Config/daily_ingest.sh   # detection only, no Claude
   bash System_Config/daily_ingest.sh             # real run
   tail -f System_Config/logs/daily_ingest.log

Disable later:
   launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
