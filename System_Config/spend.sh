#!/usr/bin/env bash
# spend.sh — API spend ledger for the headless automation.
#
# Sourced by the ingest scripts; also runnable for a report:
#   bash System_Config/spend.sh today
#   bash System_Config/spend.sh week
#   bash System_Config/spend.sh report
#
# There is no cost data anywhere else to read: ~/.claude keeps no ledger and the
# session transcripts do not record cost. The only reliable source is
# `claude -p --output-format json` -> .total_cost_usd, which run_claude now parses.
#
# Ledger: System_Config/logs/spend.log, tab-separated, append-only:
#   <YYYY-MM-DD>\t<HH:MM:SS>\t<script>\t<task>\t<usd>
#
# Context for reading the numbers: a call from this workspace costs ~$0.124 before
# doing any work (~50k tokens of CLAUDE.md + memory + skills listing load first), so
# a run of four tasks has a floor near $0.50 regardless of how little it changes.

_SPEND_SYSCFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEND_LOG="${SPEND_LOG:-$_SPEND_SYSCFG/logs/spend.log}"

mkdir -p "$(dirname "$SPEND_LOG")" 2>/dev/null || true

# spend_record <script> <task> <usd>
spend_record() {
  local script="$1" task="$2" usd="$3"
  case "$usd" in
    ''|*[!0-9.]*) return 0 ;;   # not a number — nothing to record
  esac
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%d)" "$(date +%H:%M:%S)" \
    "$script" "$task" "$usd" >> "$SPEND_LOG" 2>/dev/null || true
}

# spend_sum_since <YYYY-MM-DD>  → total USD across ledger rows on/after that date
spend_sum_since() {
  local since="$1"
  [ -r "$SPEND_LOG" ] || { echo "0.00"; return 0; }
  awk -F'\t' -v s="$since" '$1 >= s { t += $5 } END { printf "%.2f", t+0 }' "$SPEND_LOG"
}

spend_today() { spend_sum_since "$(date +%Y-%m-%d)"; }

spend_week() {
  local monday
  monday="$(date -v-Mon +%Y-%m-%d 2>/dev/null || date -d 'last monday' +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"
  spend_sum_since "$monday"
}

# spend_calls_today → number of billed calls today (useful for spotting a retry loop)
spend_calls_today() {
  [ -r "$SPEND_LOG" ] || { echo 0; return 0; }
  awk -F'\t' -v d="$(date +%Y-%m-%d)" '$1 == d { c++ } END { print c+0 }' "$SPEND_LOG"
}

# spend_breakdown_today → "script/task  $usd" lines, biggest first
spend_breakdown_today() {
  [ -r "$SPEND_LOG" ] || return 0
  awk -F'\t' -v d="$(date +%Y-%m-%d)" '$1 == d { k = $3 "/" $4; t[k] += $5 }
    END { for (k in t) printf "%.2f\t%s\n", t[k], k }' "$SPEND_LOG" \
    | sort -rn | awk -F'\t' '{ printf "  $%s  %s\n", $1, $2 }'
}

# spend_check_threshold — alert once per day when today crosses SPEND_ALERT_USD.
# Threshold lives in .notify.env so changing it never means editing a script.
spend_check_threshold() {
  local notify="$_SPEND_SYSCFG/notify.sh" env_file="$_SPEND_SYSCFG/.notify.env"
  local limit today
  [ -r "$env_file" ] && . "$env_file" 2>/dev/null || true
  limit="${SPEND_ALERT_USD:-10}"
  today="$(spend_today)"
  # Integer-safe comparison without bc: awk returns 1 when over.
  if awk -v t="$today" -v l="$limit" 'BEGIN { exit !(t+0 >= l+0) }'; then
    [ -r "$notify" ] || return 0
    bash "$notify" --event spend-threshold --severity warn \
      --dedup "$(date +%Y-%m-%d)" \
      "API spend over \$${limit} today" \
      "$(printf 'Today: $%s across %s call(s).\n\nBiggest contributors:\n%s\n\nThrottle with RAW_NOTES_BATCH in weekly_note_ingest.sh, or raise SPEND_ALERT_USD in .notify.env.' \
         "$today" "$(spend_calls_today)" "$(spend_breakdown_today)")" || true
  fi
}

# CLI mode — only when executed directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-report}" in
    today) spend_today ;;
    week)  spend_week ;;
    check) spend_check_threshold ;;
    report)
      printf 'Spend today: $%s across %s call(s)\n' "$(spend_today)" "$(spend_calls_today)"
      printf 'Spend this week: $%s\n' "$(spend_week)"
      b="$(spend_breakdown_today)"
      [ -n "$b" ] && { echo "Today by task:"; echo "$b"; }
      ;;
    *) echo "usage: spend.sh [today|week|check|report]" >&2; exit 2 ;;
  esac
fi
