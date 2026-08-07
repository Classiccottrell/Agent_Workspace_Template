#!/usr/bin/env bash
# decisions_sweep.sh — twice-daily sweep of THIS week's note for undocumented
# decisions, appended to its '## Decisions' table. Extracted from
# friday_process.sh's step C (Decisions sweep) so it runs more often than once
# a week; friday_process.sh's own step C is untouched and still runs as the
# Friday backstop.
#
# Two-tier, "free first" design: a standalone Ollama tool-calling loop
# (ollama_agent.py) is tried first, calling Ollama's local HTTP API directly —
# a SEPARATE mechanism from run_agent.sh's own "ollama" target (which shells
# out to `codex exec --oss --local-provider ollama` for general ingest and is
# untouched by this script). Kept apart deliberately: if the free tier itself
# went through codex, escalating to codex on failure would be nonsensical
# (same binary, same dependency). On failure OR a confirmed no-op, this
# escalates once to a paid claude/codex call via config.sh's
# resolve_agent_target() + run_agent.sh's run_agent() — this workspace's own
# provider-resolution machinery, not a reimplementation of it.
#
#   Activate:    bash System_Config/install_decisions_sweep.sh
#   Manual run:  bash System_Config/decisions_sweep.sh
#   Preview:     DRY_RUN=1 bash System_Config/decisions_sweep.sh

# decisions_slice <note-path> — the '## Decisions' section only (heading
# through the next '## ' heading, inclusive of that next heading line). Used
# as the no-op/change signal instead of a whole-file hash: other things (e.g.
# log_session.sh) write elsewhere in the same weekly note concurrently, and a
# whole-file hash would treat those as false "changes".
decisions_slice() {
  awk '
    /^## Decisions$/ { found=1 }
    found { print }
    found && /^## / && !/^## Decisions$/ { exit }
  ' "$1"
}

# Test seam: source this file for decisions_slice() alone, skipping `set -e`
# and everything below (which needs a real workspace) — mirrors healthcheck.sh's
# HEALTHCHECK_LIB_ONLY guard. Must run BEFORE `set -euo pipefail`: this file is
# sourced (not executed) for the lib-only case, so turning on -e here would leak
# into the sourcing shell (test.sh) for the rest of its run.
[ "${DECISIONS_SWEEP_LIB_ONLY:-0}" = "1" ] && return 0

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── CONFIG ────────────────────────────────────────────────────────────────────
WEEKLY_LOGS="$VAULT/weekly-logs"
LOG="$LOG_DIR/decisions_sweep.log"
LOCK_DIR="$LOG_DIR/decisions_sweep.lock"
OLLAMA_FREE_TIER_SECONDS="${OLLAMA_FREE_TIER_SECONDS:-2700}"  # CPU-only inference is slow
MAX_SECONDS="${MAX_SECONDS:-900}"   # escalation-tier watchdog (claude/codex)
MAX_BUDGET="${MAX_BUDGET:-2.00}"    # USD ceiling — claude only (codex has no cost flag)

# Non-interactive auth for unattended runs — same gate as daily_ingest.sh.
if [[ "${INGEST_IGNORE_KEYFILE:-0}" != "1" && -r "$HOME/.config/anthropic/key" ]]; then
  export ANTHROPIC_API_KEY="$(cat "$HOME/.config/anthropic/key")"
fi

mkdir -p "$LOG_DIR"
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "decisions_sweep start"

# ── LOCATE THIS WEEK'S NOTE (same ISO-week calc as friday_process.sh) ────────
YEAR=$(date +%G); WEEK=$(date +%V)
WEEK_TAG="${YEAR}-W${WEEK}"
NOTE_REL="weekly-logs/${WEEK_TAG}.md"
NOTE_ABS="$WEEKLY_LOGS/${WEEK_TAG}.md"

if [[ ! -d "$VAULT" ]]; then
  log "FATAL: vault dir missing: $VAULT — aborting (unmounted?)"; exit 1
fi
if [[ ! -f "$NOTE_ABS" ]]; then
  log "no weekly note for $WEEK_TAG — nothing to process; exiting"; exit 0
fi

# ── DRY RUN ───────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "── DRY RUN — would sweep $NOTE_REL for undocumented Decisions rows ──"
  echo "  → free tier: ollama_agent.py (local HTTP API, model ${OLLAMA_MODEL:-llama3.1:8b})"
  echo "  → escalation on failure/no-op: claude, then codex (via resolve_agent_target)"
  log "dry run — no agent call"; exit 0
fi

# ── CONCURRENCY LOCK (atomic mkdir; released by the EXIT trap) ────────────────
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "another decisions_sweep holds $LOCK_DIR — skipping"; exit 0
fi
cleanup() { rmdir "$LOCK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  log "note: ANTHROPIC_API_KEY unset — relying on login keychain (active GUI session only)"
fi

# ── PROMPT (adapted from friday_process.sh step C — the ONLY instruction here) ─
PROMPT="You are running headlessly for a Decisions sweep of the Vault_Brain wiki.
First read ${NOTE_REL}.

DECISIONS SWEEP. Read this week's '## Claude Sessions' entries and 'The Signal' section. For any decision described there that is NOT already reflected as a row in ${NOTE_REL}'s '## Decisions' table, APPEND one '| Decision | Rationale | Date |' row per the table's existing format — decision in past tense, rationale in one clause, date in YYYY-MM-DD. This is the backstop for the per-session judgment call ('Claude Contribution Protocol' in CLAUDE.md), since most '## Claude Sessions' lines are stamped by a deterministic no-AI hook that cannot judge whether a decision occurred. Append-only: never rewrite, reorder, or delete an existing Decisions row. If nothing qualifies, add nothing.

DO NOT edit 'Master Note.md'. DO NOT touch sources/. ${NOTE_REL} may be edited to append a Decisions row only — do not touch any other part of it (Claude Sessions, The Signal, The Noise, etc. stay off-limits). Create-or-append only; never delete; stay within this vault."

# Only the Decisions table may be touched; sources/ is denied. Unlike
# friday_process.sh, the target note itself is NOT listed here — this sweep's
# whole job is writing to that note's Decisions table, so denying it would
# code-enforce a permanent no-op.
export OLLAMA_DENY_PATHS="sources"

pre_hash="$(decisions_slice "$NOTE_ABS" | shasum -a 256 | awk '{print $1}')"

# ── FREE TIER: standalone ollama_agent.py, bypassing run_agent.sh entirely ────
# (run_agent.sh's own "ollama" target means `codex exec --oss --local-provider
# ollama` in this workspace — a different mechanism, untouched by this script.)
run_ollama_free_tier() {
  local prompt="$1" pid wd rc
  command -v python3 >/dev/null 2>&1 || return 127
  cd "$VAULT" || return 1
  python3 "$WORKSPACE/System_Config/ollama_agent.py" "$prompt" --vault "$VAULT" \
        --model "${OLLAMA_MODEL:-llama3.1:8b}" --host "${OLLAMA_HOST:-http://localhost:11434}" \
        --max-turns "${OLLAMA_MAX_TURNS:-8}" --http-timeout "${OLLAMA_HTTP_TIMEOUT:-300}" \
        >> "$LOG" 2>&1 &
  pid=$!
  ( sleep "$OLLAMA_FREE_TIER_SECONDS"; kill -TERM "$pid" 2>/dev/null
    sleep 20;                          kill -KILL "$pid" 2>/dev/null ) &
  wd=$!
  disown "$wd" 2>/dev/null || true
  if wait "$pid"; then rc=0; else rc=$?; fi
  kill "$wd" 2>/dev/null || true
  return "$rc"
}

rc=0
run_ollama_free_tier "$PROMPT" || rc=$?
post_hash="$(decisions_slice "$NOTE_ABS" | shasum -a 256 | awk '{print $1}')"
noop=0
[[ "$rc" -eq 0 && "$pre_hash" == "$post_hash" ]] && noop=1

if [[ "$rc" -ne 0 || "$noop" == "1" ]]; then
  escalated=0
  if resolve_agent_target claude || resolve_agent_target codex; then
    log "ollama free tier $( [[ "$noop" == "1" ]] && echo "NO-OPed (note unchanged)" || echo "FAILED (rc=${rc})" ) — escalating to ${AGENT_TYPE} fallback"
    source "$(dirname "${BASH_SOURCE[0]}")/run_agent.sh"
    fb_rc=0
    run_agent "$PROMPT" || fb_rc=$?
    post_hash="$(decisions_slice "$NOTE_ABS" | shasum -a 256 | awk '{print $1}')"
    if [[ "$fb_rc" -eq 0 ]]; then
      log "fallback (${AGENT_TYPE}) sweep succeeded"
      escalated=1
    else
      log "fallback (${AGENT_TYPE}) sweep also FAILED (rc=${fb_rc})"
    fi
  else
    log "no claude/codex CLI available for fallback — cannot escalate"
  fi
  if [[ "$escalated" != "1" ]]; then
    if [[ "$rc" -ne 0 ]]; then
      # A genuine failure (not just an ollama no-op) with no successful
      # fallback is worth surfacing as a non-zero exit for monitoring.
      log "sweep FAILED (rc=${rc}; may have timed out) — will retry next scheduled run"
      exit 1
    fi
    log "sweep ran OK — no undocumented decisions found (note unchanged)"
  elif [[ "$pre_hash" == "$post_hash" ]]; then
    log "sweep ran OK — no undocumented decisions found (ollama NO-OPed, fallback confirmed nothing qualifies)"
  else
    log "sweep ran OK (fallback) — Decisions table updated"
  fi
else
  log "sweep ran OK — Decisions table updated"
fi

log "decisions_sweep done — $WEEK_TAG"
