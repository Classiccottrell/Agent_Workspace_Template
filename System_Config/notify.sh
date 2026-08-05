#!/usr/bin/env bash
# notify.sh — raise a desktop notification on this machine.
#
# Two call styles. The positional form is the original and still works:
#
#   bash notify.sh "<title>" "<body>"
#
# The event form adds severity and per-event dedup:
#
#   bash notify.sh --event ingest-failed --severity fail \
#                  --dedup "<signature>" \
#                  "Ingest failed" "daily_ingest aborted at clip 3 of 7"
#
# Flags:
#   --event <id>     event identifier; namespaces the dedup state file
#   --severity <s>   info | ok | warn | fail  (default info) — sets the chip
#   --dedup <sig>    notify only if <sig> differs from the last one for --event.
#                    Use a date for once-per-day summaries.
#
# Transport: macOS Notification Center via osascript, falling back to notify-send
# where that exists. Deliberately local. This template is provider-neutral, so it
# ships no chat/webhook integration and needs no credentials or network to work.
#
# Config: System_Config/.notify.env (git-ignored, optional). See .notify.env.example.
#   NOTIFY_ENABLED=0   silence every notification
#   NOTIFY_OSASCRIPT   override the osascript binary (test seam)
#   NOTIFY_SEND_BIN    override the notify-send binary (test seam)
# An explicitly exported value always beats the file, so a caller can silence or
# redirect a single invocation without editing config.
#
# Contract:
#   exit 0 — a notification was raised, OR was deliberately suppressed
#            (NOTIFY_ENABLED=0, or an unchanged --dedup signature). Both are
#            intentional no-ops, not failed deliveries.
#   exit 1 — delivery was attempted and failed: no notifier on PATH, or the
#            notifier itself errored. The dedup signature is NOT recorded on this
#            path, so the alert retries instead of silencing itself. Callers that
#            keep their own state should do the same — healthcheck.sh wraps this
#            in persist_notification_signature for exactly that reason.
# Delivery is best-effort: no caller should abort because its alerting path failed.

# NOTIFY_CAPS=events — capability marker. Callers grep for this before passing
# event flags: an older positional-only notify.sh would treat "--event" as the
# message title and raise garbage. Do not rename this line.
set -uo pipefail   # deliberately NOT -e: a failed send must reach the exit-1 path

SYSCFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_NAME="$(basename "$(dirname "$SYSCFG")")"
ENV_FILE="$SYSCFG/.notify.env"
LOG_DIR="$SYSCFG/logs"
LOG="$LOG_DIR/notify.log"
STATE_DIR="$LOG_DIR/.notify_events"

mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG" 2>/dev/null || true; }

EVENT=""; SEVERITY="info"; DEDUP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)    EVENT="${2:-}"; shift 2 ;;
    --severity) SEVERITY="${2:-info}"; shift 2 ;;
    --dedup)    DEDUP="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) log "WARN: unknown flag $1 — ignored"; shift ;;
    *)  break ;;
  esac
done

TITLE="${1:-$WORKSPACE_NAME}"
BODY="${2:-}"

_pre_enabled="${NOTIFY_ENABLED-}"; _pre_osa="${NOTIFY_OSASCRIPT-}"; _pre_send="${NOTIFY_SEND_BIN-}"
if [[ -r "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE" || true
fi
# Caller-supplied values win over the file — see the config note in the header.
[[ -n "$_pre_enabled" ]] && NOTIFY_ENABLED="$_pre_enabled"
[[ -n "$_pre_osa" ]]     && NOTIFY_OSASCRIPT="$_pre_osa"
[[ -n "$_pre_send" ]]    && NOTIFY_SEND_BIN="$_pre_send"
true

_sig=""; _state=""

if [[ "${NOTIFY_ENABLED:-1}" != "1" ]]; then
  log "disabled (NOTIFY_ENABLED=${NOTIFY_ENABLED:-}): ${EVENT:-adhoc} — ${TITLE}"
  exit 0
fi

# ── per-event dedup ───────────────────────────────────────────────────────────
# Keyed by event id so a noisy event cannot suppress a different one. Recorded only
# after a notification is actually raised (see record_dedup below), so a failed
# delivery never silences its own retry.
if [[ -n "$DEDUP" ]]; then
  _key="${EVENT:-adhoc}"
  _key="${_key//[^A-Za-z0-9._-]/_}"
  _state="$STATE_DIR/$_key"
  _prev="$(cat "$_state" 2>/dev/null || true)"
  _sig="$(printf '%s' "$DEDUP" | shasum -a 256 2>/dev/null | awk '{print $1}')"
  if [[ -n "$_prev" && "$_sig" == "$_prev" ]]; then
    log "deduped (unchanged): ${_key} — ${TITLE}"
    exit 0
  fi
fi

record_dedup() {
  [[ -n "$DEDUP" && -n "$_state" ]] || return 0
  printf '%s' "$_sig" > "$_state" 2>/dev/null || true
}

case "$SEVERITY" in
  fail) CHIP="🔴" ;;
  warn) CHIP="🟡" ;;
  ok)   CHIP="🟢" ;;
  *)    CHIP="🔵" ;;
esac

# ── delivery ──────────────────────────────────────────────────────────────────
# Title, subtitle and body are passed as argv, never interpolated into the script
# source: a quote, backslash or newline in a check name would otherwise break the
# AppleScript rather than appear in the banner.
TITLE_LINE="$CHIP $TITLE"
SUBTITLE="$WORKSPACE_NAME${EVENT:+ · $EVENT}"
DISPLAY_BODY="${BODY:- }"
OSASCRIPT="${NOTIFY_OSASCRIPT:-osascript}"
NOTIFY_SEND="${NOTIFY_SEND_BIN:-notify-send}"

deliver_osascript() {
  command -v "$OSASCRIPT" >/dev/null 2>&1 || return 127
  "$OSASCRIPT" - "$TITLE_LINE" "$SUBTITLE" "$DISPLAY_BODY" <<'APPLESCRIPT' 2>>"$LOG"
on run argv
    display notification (item 3 of argv) with title (item 1 of argv) subtitle (item 2 of argv)
end run
APPLESCRIPT
}

deliver_notify_send() {
  command -v "$NOTIFY_SEND" >/dev/null 2>&1 || return 127
  "$NOTIFY_SEND" "$TITLE_LINE" "$DISPLAY_BODY" 2>>"$LOG"
}

if deliver_osascript || deliver_notify_send; then
  log "sent${EVENT:+ [$EVENT]}: ${TITLE}"
  record_dedup
  exit 0
fi

log "FAILED (no notifier available, or the notifier errored)${EVENT:+ [$EVENT]}: ${TITLE}"
exit 1
