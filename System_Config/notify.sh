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
# where that exists. Local delivery is unconditional and the default — it needs no
# credentials or network to work, and keeps firing whether or not anything else is
# configured. Webhook delivery (Slack, Google Chat) is additive and strictly
# opt-in via .notify.env — never required, never a substitute for local delivery.
#
# Config: System_Config/.notify.env (git-ignored, optional). See .notify.env.example.
#   NOTIFY_ENABLED=0     silence every notification
#   NOTIFY_OSASCRIPT     override the osascript binary (test seam)
#   NOTIFY_SEND_BIN      override the notify-send binary (test seam)
#   NOTIFY_CURL_BIN      override the curl binary (test seam)
#   NOTIFY_ENV_FILE       override the .notify.env path itself (test seam) — point
#                         at /dev/null (or any file without webhook vars) to test
#                         hermetically regardless of what's really configured on
#                         this machine; GCHAT_WEBHOOK_URL/SLACK_WEBHOOK_URL can't
#                         be force-blanked via env var alone (an explicitly-empty
#                         override is indistinguishable from "caller didn't set
#                         it," so the file's value would still win — this seam is
#                         the actual way to guarantee isolation)
#   GCHAT_WEBHOOK_URL     optional Google Chat webhook — opt-in, empty by default
#   SLACK_WEBHOOK_URL     optional Slack webhook — opt-in, empty by default
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
#   When both local and webhook delivery are configured, exit 0 requires only ONE
#   channel to succeed and the dedup signature is recorded on that basis — a
#   failing webhook alongside a succeeding local banner still counts as delivered
#   and will NOT retry next call. Each channel's outcome is logged independently
#   regardless of the overall exit code.
# Delivery is best-effort: no caller should abort because its alerting path failed.

# NOTIFY_CAPS=events — capability marker. Callers grep for this before passing
# event flags: an older positional-only notify.sh would treat "--event" as the
# message title and raise garbage. Do not rename this line.
set -uo pipefail   # deliberately NOT -e: a failed send must reach the exit-1 path

SYSCFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_NAME="$(basename "$(dirname "$SYSCFG")")"
ENV_FILE="${NOTIFY_ENV_FILE:-$SYSCFG/.notify.env}"
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
_pre_curl="${NOTIFY_CURL_BIN-}"; _pre_gchat="${GCHAT_WEBHOOK_URL-}"; _pre_slack="${SLACK_WEBHOOK_URL-}"
if [[ -r "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE" || true
fi
# Caller-supplied values win over the file — see the config note in the header.
[[ -n "$_pre_enabled" ]] && NOTIFY_ENABLED="$_pre_enabled"
[[ -n "$_pre_osa" ]]     && NOTIFY_OSASCRIPT="$_pre_osa"
[[ -n "$_pre_send" ]]    && NOTIFY_SEND_BIN="$_pre_send"
[[ -n "$_pre_curl" ]]    && NOTIFY_CURL_BIN="$_pre_curl"
[[ -n "$_pre_gchat" ]]   && GCHAT_WEBHOOK_URL="$_pre_gchat"
[[ -n "$_pre_slack" ]]   && SLACK_WEBHOOK_URL="$_pre_slack"
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

# ── webhook delivery (opt-in) ─────────────────────────────────────────────────
# Additive to local delivery, never a replacement. Only called when the caller
# (or .notify.env) has actually set a URL — see the empty-check below.
CURL="${NOTIFY_CURL_BIN:-curl}"

_webhook_json_esc() {
  # Same recipe as healthcheck.sh's json_esc: collapse newlines/tabs to spaces
  # (a raw newline inside a JSON string is invalid JSON), then escape \ and ".
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# deliver_webhook <name> <url> — POST a plain {"text": ...} payload (the shape
# both Slack incoming-webhooks and Google Chat webhooks accept). The URL is a
# secret: it is piped to curl via --config - (stdin), never passed as an argv
# token, so it never appears in `ps`/process-list output.
deliver_webhook() {
  local name="$1" url="$2" payload code
  command -v "$CURL" >/dev/null 2>&1 || { log "webhook [$name] FAILED (no curl on PATH)${EVENT:+ [$EVENT]}: ${TITLE}"; return 1; }
  payload="{\"text\":\"$(_webhook_json_esc "$TITLE_LINE")\\n$(_webhook_json_esc "$SUBTITLE")\\n$(_webhook_json_esc "$DISPLAY_BODY")\"}"
  code="$(printf 'url = "%s"\n' "$url" | "$CURL" --config - -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -X POST -H 'Content-Type: application/json; charset=UTF-8' -d "$payload" 2>>"$LOG")" || code=""
  case "$code" in
    2??) log "webhook [$name] sent${EVENT:+ [$EVENT]}: ${TITLE}"; return 0 ;;
    *)   log "webhook [$name] FAILED (http ${code:-none})${EVENT:+ [$EVENT]}: ${TITLE}"; return 1 ;;
  esac
}

ANY_OK=0

if deliver_osascript || deliver_notify_send; then
  log "sent${EVENT:+ [$EVENT]}: ${TITLE}"
  ANY_OK=1
else
  log "FAILED (no notifier available, or the notifier errored)${EVENT:+ [$EVENT]}: ${TITLE}"
fi

# Each webhook is independent: one failing must not block the other, and both
# outcomes are logged regardless of whether local delivery already succeeded.
[[ -n "${GCHAT_WEBHOOK_URL:-}" ]] && { deliver_webhook "gchat" "$GCHAT_WEBHOOK_URL" && ANY_OK=1; }
[[ -n "${SLACK_WEBHOOK_URL:-}" ]] && { deliver_webhook "slack" "$SLACK_WEBHOOK_URL" && ANY_OK=1; }

if [[ "$ANY_OK" -eq 1 ]]; then
  record_dedup
  exit 0
fi

exit 1
