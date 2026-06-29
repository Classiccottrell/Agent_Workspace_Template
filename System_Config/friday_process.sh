#!/usr/bin/env bash
# friday_process.sh — Weekly close-out (runs Fri 16:30 via launchd)
# Claude writes a summary to a scratch file and does append-only wiki cross-refs;
# deterministic bash then edits the Master Note row (with backup + validation +
# rollback) and stamps the close-out. The note STAYS in weekly-logs/.
#
#   Activate:    bash System_Config/install_friday_process.sh
#   Manual run:  bash System_Config/friday_process.sh
#   Preview:     DRY_RUN=1 bash System_Config/friday_process.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── CONFIG ────────────────────────────────────────────────────────────────────
# WORKSPACE / VAULT / LOG_DIR / CLAUDE come from config.sh.
WEEKLY_LOGS="$VAULT/weekly-logs"
MASTER="$VAULT/Master Note.md"
LOG="$LOG_DIR/friday_process.log"
LOCK_DIR="$LOG_DIR/friday_process.lock"
SENTINEL="<!-- WEEKLY-INDEX-INSERT -->"
MAX_SECONDS="${MAX_SECONDS:-900}"
MAX_BUDGET="${MAX_BUDGET:-2.00}"

if [[ -r "$HOME/.config/anthropic/key" ]]; then
  export ANTHROPIC_API_KEY="$(cat "$HOME/.config/anthropic/key")"
fi

mkdir -p "$LOG_DIR"
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "friday_process start"

# ── LOCATE THIS WEEK'S NOTE ───────────────────────────────────────────────────
YEAR=$(date +%G); WEEK=$(date +%V); TODAY=$(date +%Y-%m-%d)
WEEK_TAG="${YEAR}-W${WEEK}"
NOTE_REL="weekly-logs/${WEEK_TAG}.md"
NOTE_ABS="$WEEKLY_LOGS/${WEEK_TAG}.md"
SUMMARY_REL="weekly-logs/.${WEEK_TAG}.summary.txt"
SUMMARY_ABS="$WEEKLY_LOGS/.${WEEK_TAG}.summary.txt"

if [[ ! -d "$VAULT" ]]; then
  log "FATAL: vault dir missing: $VAULT — aborting (unmounted?)"; exit 1
fi
if [[ ! -f "$NOTE_ABS" ]]; then
  log "no weekly note for $WEEK_TAG — nothing to process; exiting"; exit 0
fi

# ── IDEMPOTENCY GUARD ─────────────────────────────────────────────────────────
if grep -qF "${TODAY}: Friday close-out" "$NOTE_ABS"; then
  log "already closed out for ${TODAY} — nothing to do; exiting"; exit 0
fi

# ── DRY RUN ───────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "── DRY RUN — would process $NOTE_REL ──"
  echo "  → Claude writes a 1–2 sentence summary to ${SUMMARY_REL} + appends wiki cross-refs"
  echo "  → bash edits the Master Note row for [[${WEEK_TAG}]] deterministically (backup + validate + rollback)"
  echo "  → bash stamps a close-out line into the note's Claude Sessions (note stays in weekly-logs/)"
  log "dry run — no Claude call"; exit 0
fi

# ── CONCURRENCY LOCK (atomic mkdir; released by the EXIT trap) ────────────────
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "another friday_process holds $LOCK_DIR — skipping"; exit 0
fi
cleanup() {
  chmod u+w "$VAULT/sources"/*.md 2>/dev/null || true
  rm -f "$SUMMARY_ABS" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  log "note: ANTHROPIC_API_KEY unset — relying on login keychain (active GUI session only)"
fi

# Backstop: lock source clips read-only (this job must not touch sources/).
chmod a-w "$VAULT/sources"/*.md 2>/dev/null || true
rm -f "$SUMMARY_ABS" 2>/dev/null || true

# ── CLAUDE: summary text + append-only cross-refs (NEVER edits the Master Note) ─
PROMPT="You are running headlessly for the Friday weekly close-out of the Vault_Brain wiki.
First read CLAUDE.md for the schema, then read ${NOTE_REL}.

Do exactly two things:

A. SUMMARY → scratch file. Write a single-line 1–2 sentence summary of what actually mattered this week (drawn from 'The Signal', 'Decisions', and 'Claude Sessions') to the file ${SUMMARY_REL} using the Write tool. One line only: NO newlines, and do NOT use the '|' character (it breaks the table). Write nothing else to that file.

B. CROSS-REFERENCES. For each project/entity named in a '#### Heading' under 'The Signal' and 'The Noise':
   - If a matching wiki/ page exists: FIRST scan the WHOLE page for an existing [[${WEEK_TAG}]] link — if it appears anywhere, do not add another. Otherwise APPEND a single '- [[${WEEK_TAG}]]' under the page's '## Connections' section ONLY (never under Sources — Sources is only for source documents). You may also append one genuinely new fact. Never rewrite or delete existing content.
   - If no page exists and it is a substantive ongoing project/technology/person, create one per CLAUDE.md's page format and add it to wiki/_index.md.
   - Skip trivial one-off tasks and bare links.

DO NOT edit 'Master Note.md'. DO NOT edit ${NOTE_REL}. DO NOT touch sources/. Create-or-append only; never delete; stay within this vault."

run_claude() {
  cd "$VAULT"
  if [[ "${AGENT_TYPE:-}" == "gemini" ]]; then
    "$CLAUDE" -p "$PROMPT" \
          --sandbox \
          --dangerously-skip-permissions >> "$LOG" 2>&1 &
  else
    "$CLAUDE" -p "$PROMPT" \
          --allowedTools "Read,Write,Edit,Glob,Grep" \
          --disallowedTools "Bash,KillShell,Task,WebFetch,WebSearch,NotebookEdit" \
          --permission-mode acceptEdits \
          --max-budget-usd "$MAX_BUDGET" >> "$LOG" 2>&1 &
  fi
  local pid wd rc
  pid=$!
  ( sleep "$MAX_SECONDS"; kill -TERM "$pid" 2>/dev/null ) &
  wd=$!
  disown "$wd" 2>/dev/null || true
  if wait "$pid"; then rc=0; else rc=$?; fi
  kill "$wd" 2>/dev/null || true
  return "$rc"
}

if ! run_claude; then
  rc=$?
  log "claude step FAILED (rc=${rc}; may have timed out after ${MAX_SECONDS}s) — Master Note untouched; will retry next run"
  exit 1
fi

# ── DETERMINISTIC MASTER NOTE EDIT (backup → awk row rewrite → validate → rollback) ─
if [[ ! -s "$SUMMARY_ABS" ]]; then
  log "claude produced no summary at ${SUMMARY_REL} — Master Note left unchanged; exiting"
  exit 1
fi
# Sanitize: strip newlines and any pipe chars that would break the table cell.
SUMMARY=$(tr -d '\r\n' < "$SUMMARY_ABS" | sed 's/|/\//g; s/^[[:space:]]*//; s/[[:space:]]*$//')

if [[ -f "$MASTER" ]]; then
  BACKUP="$LOG_DIR/master.$(date +%s).bak"
  cp "$MASTER" "$BACKUP"
  pre_rows=$(grep -cE '^\| \[\[' "$MASTER" || true)

  # Rewrite ONLY field 6 of the row whose trimmed first cell == [[WEEK_TAG]].
  set +e
  awk -F'|' -v tag="[[${WEEK_TAG}]]" -v sum=" ${SUMMARY} " '
    BEGIN { OFS="|" }
    { c2=$2; gsub(/^[ \t]+|[ \t]+$/,"",c2)
      if (c2==tag && NF>=6) { $6=sum; hit=1 }
      print }
    END { exit (hit?0:3) }
  ' "$MASTER" > "$MASTER.tmp"
  awk_rc=$?
  set -e

  post_rows=$(grep -cE '^\| \[\[' "$MASTER.tmp" 2>/dev/null || true)
  if [[ $awk_rc -ne 0 ]]; then
    rm -f "$MASTER.tmp"
    log "WARNING: no Master Note row matched [[${WEEK_TAG}]] (awk_rc=$awk_rc) — summary not written; backup at $BACKUP"
  elif ! grep -Fq "$SENTINEL" "$MASTER.tmp" || [[ "$post_rows" -ne "$pre_rows" ]]; then
    rm -f "$MASTER.tmp"
    log "VALIDATION FAILED — sentinel missing or row count ${pre_rows}->${post_rows}; Master Note left unchanged (backup $BACKUP)"
  else
    mv "$MASTER.tmp" "$MASTER"
    log "Master Note summary written for $WEEK_TAG (backup $BACKUP)"
  fi
else
  log "WARNING: Master Note not found at $MASTER — summary not written"
fi

# ── STAMP CLOSE-OUT into the note's Claude Sessions (deterministic) ───────────
CLOSEOUT="- ${TODAY}: Friday close-out — summarized week to Master Note; cross-references updated"
awk -v line="$CLOSEOUT" '
  $0=="## Claude Sessions" { incs=1 }
  incs && /^---[[:space:]]*$/ && !done { print line; done=1; incs=0 }
  { print }
  END { if (!done) print line }
' "$NOTE_ABS" > "$NOTE_ABS.tmp" && mv "$NOTE_ABS.tmp" "$NOTE_ABS" || rm -f "$NOTE_ABS.tmp"

# ── WEEKEND-CHANGE BASELINE ───────────────────────────────────────────────────
# Snapshot the just-closed note. monday_init.sh diffs this against the note's
# Monday-morning state to detect — and merge forward — any weekend edits.
SNAP_ABS="$WEEKLY_LOGS/.${WEEK_TAG}.fridayclose.snapshot.md"
if cp "$NOTE_ABS" "$SNAP_ABS" 2>/dev/null; then
  log "weekend-change baseline saved: .${WEEK_TAG}.fridayclose.snapshot.md"
else
  log "WARNING: could not write Friday-close snapshot for $WEEK_TAG"
fi

log "friday_process done — $WEEK_TAG closed out OK"
# Regenerate microsite from live source files
if command -v python3 >/dev/null 2>&1 && [ -f "$SYSCFG/gen_site.py" ]; then
  python3 "$SYSCFG/gen_site.py" && echo "[friday_process] docs/index.html regenerated."
fi
