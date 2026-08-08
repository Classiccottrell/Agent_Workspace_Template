#!/usr/bin/env bash
# install_decisions_sweep.sh — activate the twice-daily Decisions-sweep
# LaunchAgent. Safe to re-run (idempotent): it renders the plist template,
# reinstalls, and reloads the agent. The launchd label and all paths are
# derived at runtime, so this works wherever the workspace is cloned.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
validate_config || { echo "aborting: invalid config" >&2; exit 1; }

SYSCFG="$WORKSPACE/System_Config"
LABEL="$LABEL_PREFIX.decisionssweep"
TMPL="$SYSCFG/decisionssweep.plist.tmpl"
PLIST_NAME="$LABEL.plist"
DEST_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
UID_NUM="$(id -u)"

# ── Non-macOS: launchd is unavailable — fall back per $SCHEDULER (config.sh) ──
if [[ "${SCHEDULER:-launchd}" != "launchd" ]]; then
  if [[ "$SCHEDULER" == "cron" ]]; then
    mkdir -p "$SYSCFG/logs"
    install_cron_job "decisionssweep-noon" "$DECISIONSSWEEP_NOON_MINUTE $DECISIONSSWEEP_NOON_HOUR * * *" "$SYSCFG/decisions_sweep.sh"
    install_cron_job "decisionssweep-evening" "$DECISIONSSWEEP_EVENING_MINUTE $DECISIONSSWEEP_EVENING_HOUR * * *" "$SYSCFG/decisions_sweep.sh"
  else
    echo "No supported scheduler on this OS (need launchd or cron)."
    echo "Run manually or schedule yourself: bash System_Config/decisions_sweep.sh"
  fi
  exit 0
fi

echo "→ Creating log dir (must exist before launchd opens its redirect targets)…"
mkdir -p "$SYSCFG/logs" "$LAUNCHD_LOG_DIR" "$HOME/Library/LaunchAgents"

echo "→ Rendering $TMPL → $DEST_PLIST (label: $LABEL, schedule: ${DECISIONSSWEEP_NOON_HOUR}:$(printf '%02d' "$DECISIONSSWEEP_NOON_MINUTE") + ${DECISIONSSWEEP_EVENING_HOUR}:$(printf '%02d' "$DECISIONSSWEEP_EVENING_MINUTE"))"
sed -e "s|__LABEL__|$LABEL|g" \
    -e "s|__WORKSPACE_ROOT__|$WORKSPACE|g" \
    -e "s|__LOG_DIR__|$LAUNCHD_LOG_DIR|g" \
    -e "s|__DECISIONSSWEEP_NOON_HOUR__|$DECISIONSSWEEP_NOON_HOUR|g" \
    -e "s|__DECISIONSSWEEP_NOON_MINUTE__|$DECISIONSSWEEP_NOON_MINUTE|g" \
    -e "s|__DECISIONSSWEEP_EVENING_HOUR__|$DECISIONSSWEEP_EVENING_HOUR|g" \
    -e "s|__DECISIONSSWEEP_EVENING_MINUTE__|$DECISIONSSWEEP_EVENING_MINUTE|g" \
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
  decisions_sweep.sh uses it automatically if present (INGEST_IGNORE_KEYFILE=0).

COST NOTE: this job always tries a local, free Ollama call first (via
  ollama_agent.py against Ollama's HTTP API — separate from the INGEST_TARGETS
  ollama path). Only a failed or no-op ollama attempt escalates once to a paid
  claude/codex call, so worst case is up to 2 paid fallback calls/day, each
  capped at MAX_BUDGET (default \$2.00) — a ~\$4/day ceiling. Requires Ollama
  running locally (${OLLAMA_HOST:-http://localhost:11434}) with a model pulled
  (default llama3.1:8b, or set OLLAMA_MODEL); without Ollama reachable, every
  run escalates straight to the paid tier.

Test it now without waiting for the next scheduled fire:
   DRY_RUN=1 bash System_Config/decisions_sweep.sh   # detection only, no agent call
   bash System_Config/decisions_sweep.sh             # real run
   tail -f System_Config/logs/decisions_sweep.log

Disable later:
   launchctl bootout gui/$UID_NUM/$LABEL
────────────────────────────────────────────────────────────────────────────
NOTE
