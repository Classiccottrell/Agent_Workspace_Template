#!/usr/bin/env bash
# notify.sh — push a message to Google Chat as a rich card (with fallbacks).
#
# Two call styles. The positional form is the original and still works:
#
#   bash notify.sh "<title>" "<body>"
#
# The event form adds severity, threading, buttons, per-event dedup and the
# vault-content gate:
#
#   bash notify.sh --event ingest-failed --severity fail \
#                  --thread automation-2026-08-04 \
#                  --button "Open dashboard|https://example.com/status" \
#                  --dedup "<signature>" \
#                  "Ingest failed" "daily_ingest aborted at clip 3 of 7"
#
# Flags:
#   --event <id>        event identifier; namespaces the dedup state file
#   --severity <s>      info | ok | warn | fail   (default info) — sets the chip
#   --thread <key>      Chat threadKey; the same key groups messages in one thread
#   --button "L|URL"    add a link button (repeatable; http/https only)
#   --dedup <sig>       send only if <sig> differs from the last one for --event.
#                       Use a date for once-per-day summaries.
#   --content           marks the payload as containing vault content (note titles,
#                       clip filenames, decision text). Suppressed unless
#                       GCHAT_INCLUDE_CONTENT=1 — this posts into a corporate space.
#   --style card|text   override GCHAT_STYLE (default card)
#
# Config: System_Config/.notify.env (git-ignored — the webhook URL embeds a secret
# token). See .notify.env.example.
#
# Contract: this script NEVER fails its caller. Missing config, dead network, a 4xx
# from Chat, or a malformed card all exit 0 after logging. An alerting path must not
# be able to break the job it reports on.

# NOTIFY_CAPS=events — capability marker. Callers grep for this before passing
# v2 flags: an older positional-only notify.sh would treat "--event" as the
# message title and post garbage to the space. Do not rename this line.
set -uo pipefail   # deliberately NOT -e: see contract above

SYSCFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SYSCFG/.notify.env"
LOG_DIR="$SYSCFG/logs"
LOG="$LOG_DIR/notify.log"
STATE_DIR="$LOG_DIR/.notify_events"

mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG" 2>/dev/null || true; }

EVENT=""; SEVERITY="info"; THREAD=""; DEDUP=""; IS_CONTENT=0; STYLE=""
BUTTONS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)    EVENT="${2:-}"; shift 2 ;;
    --severity) SEVERITY="${2:-info}"; shift 2 ;;
    --thread)   THREAD="${2:-}"; shift 2 ;;
    --button)   BUTTONS+=("${2:-}"); shift 2 ;;
    --dedup)    DEDUP="${2:-}"; shift 2 ;;
    --content)  IS_CONTENT=1; shift ;;
    --style)    STYLE="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) log "WARN: unknown flag $1 — ignored"; shift ;;
    *)  break ;;
  esac
done

TITLE="${1:-Directory_2026}"
BODY="${2:-}"

if [[ -r "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE" || true
fi

STYLE="${STYLE:-${GCHAT_STYLE:-card}}"
_sig=""; _state=""

# ── vault-content gate ────────────────────────────────────────────────────────
# Several event types (new wiki pages, decision text, clip filenames, Rally item
# titles) inherently carry vault content. Opt in explicitly rather than leaking it.
if [[ "$IS_CONTENT" == "1" && "${GCHAT_INCLUDE_CONTENT:-0}" != "1" ]]; then
  log "suppressed (content gate; set GCHAT_INCLUDE_CONTENT=1 to allow): ${EVENT:-adhoc} — ${TITLE}"
  exit 0
fi

# ── per-event dedup ───────────────────────────────────────────────────────────
# Keyed by event id so a noisy event cannot suppress a different one. Recorded only
# after a send is attempted, so a gated send never poisons the state.
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

case "$SEVERITY" in
  fail) CHIP="🔴" ;;
  warn) CHIP="🟡" ;;
  ok)   CHIP="🟢" ;;
  *)    CHIP="🔵" ;;
esac

notify_local() {
  local t="${1//\"/}" b="${2//\"/}"
  b="${b//$'\n'/ }"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${b}\" with title \"${t}\"" >/dev/null 2>&1 || true
  fi
}

record_dedup() {
  [[ -n "$DEDUP" && -n "$_state" ]] || return 0
  printf '%s' "$_sig" > "$_state" 2>/dev/null || true
}

if [[ -z "${GCHAT_WEBHOOK_URL:-}" ]]; then
  log "no-op: GCHAT_WEBHOOK_URL unset (create $ENV_FILE to enable Chat delivery) — ${TITLE}"
  [[ "${GCHAT_FALLBACK_LOCAL:-0}" == "1" ]] && notify_local "$TITLE" "$BODY"
  record_dedup
  exit 0
fi

# ── build the payload ─────────────────────────────────────────────────────────
# python3 does the encoding so quotes, newlines and unicode cannot produce malformed
# JSON. Card widgets are limited to textParagraph + buttonList: both are universally
# supported, whereas an invalid startIcon enum would 400 the entire send.
PAYLOAD="$(
  TITLE="$TITLE" BODY="$BODY" CHIP="$CHIP" \
  EVENT="$EVENT" STYLE="$STYLE" THREAD="$THREAD" \
  BUTTONS="$(printf '%s\n' "${BUTTONS[@]+"${BUTTONS[@]}"}")" \
  python3 -c '
import json, os, html

title  = os.environ.get("TITLE", "")
body   = os.environ.get("BODY", "")
chip   = os.environ.get("CHIP", "")
event  = os.environ.get("EVENT", "")
style  = os.environ.get("STYLE", "card")
thread = os.environ.get("THREAD", "")

buttons = []
for line in os.environ.get("BUTTONS", "").split("\n"):
    line = line.strip()
    if not line or "|" not in line:
        continue
    label, url = line.split("|", 1)
    label, url = label.strip(), url.strip()
    # Chat rejects non-http(s) button links; skip rather than 400 the whole message.
    if label and url.startswith(("http://", "https://")):
        buttons.append({"text": label, "onClick": {"openLink": {"url": url}}})

msg = {}

if style == "card":
    widgets = []
    if body:
        widgets.append({"textParagraph": {"text": html.escape(body).replace("\n", "<br>")}})
    if buttons:
        widgets.append({"buttonList": {"buttons": buttons}})
    if not widgets:
        widgets.append({"textParagraph": {"text": " "}})
    subtitle = "Directory_2026" + (" · " + event if event else "")
    msg["cardsV2"] = [{
        "cardId": (event or "notify") + "-card",
        "card": {
            "header": {"title": "{} {}".format(chip, title).strip(), "subtitle": subtitle},
            "sections": [{"widgets": widgets}],
        },
    }]
else:
    text = "{} *{}*".format(chip, title)
    if body:
        text += "\n" + body
    for b in buttons:
        text += "\n" + b["onClick"]["openLink"]["url"]
    msg["text"] = text

if thread:
    msg["thread"] = {"threadKey": thread}

print(json.dumps(msg))
' 2>>"$LOG"
)"

if [[ -z "$PAYLOAD" ]]; then
  log "ERROR: could not encode payload — ${TITLE}"
  notify_local "$TITLE" "$BODY"
  record_dedup
  exit 0
fi

URL="$GCHAT_WEBHOOK_URL"
# Threading requires the reply option; without it Chat rejects an unknown threadKey.
if [[ -n "$THREAD" ]]; then
  case "$URL" in
    *messageReplyOption=*) : ;;
    *\?*) URL="${URL}&messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD" ;;
    *)    URL="${URL}?messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD" ;;
  esac
fi

RESP="$(mktemp "${TMPDIR:-/tmp}/notify_resp.XXXXXX" 2>/dev/null || echo "/tmp/notify_resp.$$")"
HTTP_CODE="$(curl -sS -o "$RESP" -w '%{http_code}' \
  --max-time 20 \
  -X POST \
  -H 'Content-Type: application/json; charset=UTF-8' \
  -d "$PAYLOAD" \
  "$URL" 2>>"$LOG")"

if [[ "$HTTP_CODE" == "200" ]]; then
  log "sent (200)${EVENT:+ [$EVENT]}: ${TITLE}"
  [[ "${GCHAT_FALLBACK_LOCAL:-0}" == "1" ]] && notify_local "$TITLE" "$BODY"
else
  log "FAILED (http ${HTTP_CODE:-none})${EVENT:+ [$EVENT]}: ${TITLE} — $(head -c 300 "$RESP" 2>/dev/null | tr '\n' ' ')"
  # A card Chat rejects should still reach the user as plain text. GCHAT_NO_RETRY
  # guards the one-level recursion.
  if [[ "$STYLE" == "card" && "$HTTP_CODE" == "400" && -z "${GCHAT_NO_RETRY:-}" ]]; then
    log "retrying as plain text: ${TITLE}"
    GCHAT_NO_RETRY=1 bash "$SYSCFG/notify.sh" --style text ${EVENT:+--event "$EVENT"} \
      --severity "$SEVERITY" ${THREAD:+--thread "$THREAD"} "$TITLE" "$BODY" >/dev/null 2>&1 || true
  else
    notify_local "$TITLE" "$BODY"
  fi
fi
rm -f "$RESP" 2>/dev/null || true

record_dedup
exit 0
