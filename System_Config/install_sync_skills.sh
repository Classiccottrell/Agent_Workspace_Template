#!/usr/bin/env bash
# install_sync_skills.sh — activate the skill-sync LaunchAgent (idempotent).
# Syncs skills installed via `npx skills add -g` (→ ~/.agents/skills/) into
# ~/.claude/skills/ and flags unindexed entries in master-orchestrator.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
validate_config || { echo "aborting: invalid config" >&2; exit 1; }

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.syncskills"
TMPL="$SYSCFG/syncskills.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

# ── Non-macOS: launchd is unavailable — fall back per $SCHEDULER (config.sh) ──
if [[ "${SCHEDULER:-launchd}" != "launchd" ]]; then
  if [[ "$SCHEDULER" == "cron" ]]; then
    mkdir -p "$SYSCFG/logs"
    install_cron_job "syncskills" "0 * * * *" "$SYSCFG/sync-skills.sh"
  else
    echo "No supported scheduler on this OS (need launchd or cron)."
    echo "Run manually or schedule yourself: bash System_Config/sync-skills.sh"
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
  echo "  (check with: launchctl list | grep syncskills)"

cat <<NOTE

────────────────────────────────────────────────────────────────────────────
Skill sync agent installed. Fires on npx skills add -g + hourly + at login.
  Watch: ~/.agents/skills  →  ~/.claude/skills  →  master-orchestrator index

Manual run:   bash System_Config/sync-skills.sh
Logs:         System_Config/logs/sync-skills.log
Disable:      launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
