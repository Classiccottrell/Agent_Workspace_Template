#!/usr/bin/env bash
# install_vault_snapshot.sh — activate the Vault_Brain daily git snapshot LaunchAgent.
# Safe to re-run (idempotent): it renders the plist template, reinstalls, and
# reloads the agent. The launchd label and all paths are derived at runtime, so
# this works wherever the workspace is cloned.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
validate_config || { echo "aborting: invalid config" >&2; exit 1; }

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.vaultsnapshot"
TMPL="$SYSCFG/vaultsnapshot.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

# Runs an hour after the daily ingest, at :15 past, so it snapshots whatever
# ingest wrote plus any manual edits made during the day.
SNAP_HOUR=$(( (INGEST_HOUR + 1) % 24 ))

# ── Non-macOS: launchd is unavailable — fall back per $SCHEDULER (config.sh) ──
if [[ "${SCHEDULER:-launchd}" != "launchd" ]]; then
  if [[ "$SCHEDULER" == "cron" ]]; then
    mkdir -p "$SYSCFG/logs"
    install_cron_job "vaultsnapshot" "15 $SNAP_HOUR * * *" "$SYSCFG/vault_snapshot.sh"
  else
    echo "No supported scheduler on this OS (need launchd or cron)."
    echo "Run manually or schedule yourself: bash System_Config/vault_snapshot.sh"
  fi
  exit 0
fi

echo "→ Creating log dir (must exist before launchd opens its redirect targets)…"
mkdir -p "$SYSCFG/logs" "$LAUNCHD_LOG_DIR" "$HOME/Library/LaunchAgents"

echo "→ Rendering $TMPL → $DEST_PLIST (label: $LABEL, schedule: ${SNAP_HOUR}:15)"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__WORKSPACE_ROOT__|$WORKSPACE|g" \
    -e "s|__LOG_DIR__|$LAUNCHD_LOG_DIR|g" \
    -e "s|__SNAP_HOUR__|$SNAP_HOUR|g" \
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
NOTE: this snapshot runs one hour after daily_ingest (${SNAP_HOUR}:15, vs
ingest's ${INGEST_HOUR}:$(printf '%02d' "$INGEST_MINUTE")), so it captures
whatever ingest wrote that morning plus any manual vault edits.

Test it now without waiting for the scheduled time:
   bash System_Config/vault_snapshot.sh
   tail -f System_Config/logs/vault_snapshot.log

Disable later:
   launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
