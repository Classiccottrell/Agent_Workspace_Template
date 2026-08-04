#!/usr/bin/env bash
# notify.sh — push a short message to Google Chat (with a local-notification fallback).
#
# Usage:
#   bash System_Config/notify.sh "<title>" "<body>"
#
# Config: System_Config/.notify.env (git-ignored — the webhook URL embeds a secret
# token, so it must never enter the repo). Copy .notify.env.example and fill in:
#
#   GCHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/AAA.../messages?key=...&token=..."
#   GCHAT_FALLBACK_LOCAL=1     # optional: also raise a macOS notification
#
# Create the webhook: open the target Chat space -> expand-more arrow next to the
# space title -> Apps & integrations -> Add webhooks -> name + avatar -> Save ->
# copy the URL. Requires the Workspace admin setting "let users add and use
# incoming webhooks"; the button is greyed out when the org has it disabled.
#
# Contract: this script NEVER fails its caller. A missing config, a dead network or
# a 4xx from Chat all exit 0 after logging — an alerting path must not be able to
# break the job it reports on.
#
# Payload policy: callers pass counts, check names and job names only. Never vault
# content, note titles or clip filenames — this posts into a corporate Chat space.

set -uo pipefail   # deliberately NOT -e: see contract above

SYSCFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SYSCFG/.notify.env"
LOG_DIR="$SYSCFG/logs"
LOG="$LOG_DIR/notify.log"

mkdir -p "$LOG_DIR" 2>/dev/null || true
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG" 2>/dev/null || true; }

TITLE="${1:-Directory_2026}"
BODY="${2:-}"

if [[ -r "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE" || true
fi

notify_local() {
  # Best-effort macOS banner. Quotes are stripped rather than escaped: this is a
  # fallback path and osascript quoting is not worth a second failure mode.
  local t="${1//\"/}" b="${2//\"/}"
  b="${b//$'\n'/ }"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${b}\" with title \"${t}\"" >/dev/null 2>&1 || true
  fi
}

if [[ -z "${GCHAT_WEBHOOK_URL:-}" ]]; then
  log "no-op: GCHAT_WEBHOOK_URL unset (create $ENV_FILE to enable Chat delivery) — ${TITLE}"
  [[ "${GCHAT_FALLBACK_LOCAL:-0}" == "1" ]] && notify_local "$TITLE" "$BODY"
  exit 0
fi

# Build the payload with python3 so quotes, newlines and unicode in the body cannot
# produce malformed JSON.
PAYLOAD="$(TITLE="$TITLE" BODY="$BODY" python3 -c '
import json, os
title = os.environ.get("TITLE", "")
body = os.environ.get("BODY", "")
text = "*{}*\n{}".format(title, body) if body else "*{}*".format(title)
print(json.dumps({"text": text}))
' 2>/dev/null)"

if [[ -z "$PAYLOAD" ]]; then
  log "ERROR: could not encode payload — ${TITLE}"
  notify_local "$TITLE" "$BODY"
  exit 0
fi

HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' \
  --max-time 20 \
  -X POST \
  -H 'Content-Type: application/json; charset=UTF-8' \
  -d "$PAYLOAD" \
  "$GCHAT_WEBHOOK_URL" 2>>"$LOG")"

if [[ "$HTTP_CODE" == "200" ]]; then
  log "sent (200): ${TITLE}"
  [[ "${GCHAT_FALLBACK_LOCAL:-0}" == "1" ]] && notify_local "$TITLE" "$BODY"
else
  log "FAILED (http ${HTTP_CODE:-none}): ${TITLE} — falling back to local notification"
  notify_local "$TITLE" "$BODY"
fi

exit 0
