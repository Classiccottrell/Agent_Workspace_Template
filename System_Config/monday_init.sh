#!/usr/bin/env bash
# monday_init.sh — Weekly Workspace Initializer
# Creates this week's note from the template (filling Sprint + Quarter) and adds
# a row to the Master Note's Weekly Index. Idempotent: skips if the note exists.
# All date values are anchored to the MONDAY of the current ISO week, so the
# note is correct no matter which weekday the script runs.
#
#   Run manually:  bash System_Config/monday_init.sh
#   Preview:       DRY_RUN=1 bash System_Config/monday_init.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── CONFIG ────────────────────────────────────────────────────────────────────
# WORKSPACE / VAULT / LOG_DIR come from config.sh.
TEMPLATE="$VAULT/Weekly_Note_Template.md"
WEEKLY_LOGS="$VAULT/weekly-logs"
MASTER="$VAULT/Master Note.md"
INDEX_SENTINEL="<!-- WEEKLY-INDEX-INSERT -->"

mkdir -p "$WEEKLY_LOGS" "$LOG_DIR"

# ── DATE CALCULATION (anchored to Monday of the current ISO week) ─────────────
DOW=$(date +%u)                                                  # 1=Mon .. 7=Sun
MONDAY=$(date -v-$((DOW-1))d +%Y-%m-%d 2>/dev/null || date -d "-$((DOW-1)) days" +%Y-%m-%d)
# Format an offset (in days) from MONDAY — BSD date, with GNU fallback.
fmt() { date -j -v+"$1"d -f "%Y-%m-%d" "$MONDAY" +"$2" 2>/dev/null || date -d "$MONDAY +$1 days" +"$2"; }

YEAR=$(fmt 0 %G)                  # ISO week-year (pairs with %V)
WEEK_NUM=$(fmt 0 %V)              # zero-padded ISO week
WEEK_N=$((10#$WEEK_NUM))
MONTH_N=$((10#$(fmt 0 %m)))
DATE_START=$MONDAY
DATE_END=$(fmt 4 %Y-%m-%d)        # Friday
INIT_DATE=$(date +%Y-%m-%d)       # actual run date

# Sprint = ceil(ISO week / 2)  →  W25 = 13, W26 = 13, W27 = 14
SPRINT=$(( (WEEK_N + 1) / 2 ))

# Quarter = standard calendar quarter (Q1 Jan–Mar · Q2 Apr–Jun · Q3 Jul–Sep · Q4 Oct–Dec).
# Adjust this mapping to match your own fiscal calendar if it differs.
case "$MONTH_N" in
  1|2|3)    QUARTER=1 ;;
  4|5|6)    QUARTER=2 ;;
  7|8|9)    QUARTER=3 ;;
  10|11|12) QUARTER=4 ;;
  *)        QUARTER="?" ;;
esac

# Human label, e.g. "Jun 16–20" (or "Jun 30 – Jul 4" across a month edge)
MON_ABBR=$(fmt 0 %b); D_START=$((10#$(fmt 0 %d)))
END_MON=$(fmt 4 %b);  D_END=$((10#$(fmt 4 %d)))
if [[ "$END_MON" == "$MON_ABBR" ]]; then
  WEEK_LABEL="${MON_ABBR} ${D_START}–${D_END}"
else
  WEEK_LABEL="${MON_ABBR} ${D_START} – ${END_MON} ${D_END}"
fi

NOTE_FILE="$WEEKLY_LOGS/${YEAR}-W${WEEK_NUM}.md"
WIKILINK="[[${YEAR}-W${WEEK_NUM}]]"
INDEX_ROW="| ${WIKILINK} | ${SPRINT} | Q${QUARTER} | ${WEEK_LABEL} | _pending Friday summary_ |"

# ── DRY RUN ───────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "Would create: $NOTE_FILE  (Monday-anchored: $MONDAY → $DATE_END)"
  echo "  Sprint $SPRINT | Q$QUARTER | $WEEK_LABEL"
  echo "Master Note row: $INDEX_ROW"
  [[ -f "$NOTE_FILE" ]] && echo "(note already exists — real run would skip)"
  echo "Would create Raw_Notes folder: $VAULT/Raw_Notes/${YEAR}/W${WEEK_NUM} ${WEEK_LABEL}"
  exit 0
fi

# ── CREATE Raw_Notes WEEK FOLDER (always, idempotent) ───────────────────────
mkdir -p "$VAULT/Raw_Notes/${YEAR}/W${WEEK_NUM} ${WEEK_LABEL}"
echo "[monday_init] Raw_Notes folder ready: Raw_Notes/${YEAR}/W${WEEK_NUM} ${WEEK_LABEL}"

# ── GUARD: skip if note already exists ───────────────────────────────────────
if [[ -f "$NOTE_FILE" ]]; then
  echo "[monday_init] Note already exists: $NOTE_FILE — skipping."
  exit 0
fi

echo "[monday_init] Initializing W${WEEK_NUM} ${YEAR} — Sprint ${SPRINT}, Q${QUARTER}"

# ── CARRY FORWARD open action items from the previous ISO week ────────────────
# Previous week derived from MONDAY−7d (handles year/W01 rollover correctly).
PY=$(date -v-7d -j -f "%Y-%m-%d" "$MONDAY" +%G 2>/dev/null || date -d "$MONDAY -7 days" +%G)
PW=$(date -v-7d -j -f "%Y-%m-%d" "$MONDAY" +%V 2>/dev/null || date -d "$MONDAY -7 days" +%V)
PREV_NOTE="$WEEKLY_LOGS/${PY}-W${PW}.md"
CARRIED=""
if [[ -f "$PREV_NOTE" ]]; then
  # Group each open task under its '#### Project' header. A header is emitted
  # only if it has >=1 open '- [ ]' item; indented sub-bullets/context lines
  # under an open item are carried with it. Safeguards: stop at the cheat-sheet
  # stop at Decisions (permanent record, not carried forward); ignore 'Carried From' /
  # 'Weekend Edits' blocks (so items don't re-carry), drop 'Action item one'.
  CARRIED=$(awk '
    /^## Decisions/                            { exit }
    /^## Carried From/ || /^## Weekend Edits/  { skip=1; hdr=""; printed=0; cap=0; next }
    /^## /                  { skip=0; hdr=""; cap=0; next }
    skip                    { next }
    /^#### /                { hdr=$0; printed=0; cap=0; next }
    /^---[[:space:]]*$/     { cap=0; next }
    /^[[:space:]]*-[[:space:]]*\[ \]/ {
        if ($0 ~ /Action item one/) { cap=0; next }
        if (hdr != "" && !printed) { print ""; print hdr; printed=1 }
        print; cap=1; next
    }
    /^[[:space:]]*-[[:space:]]*\[[^ ]\]/ { cap=0; next }
    cap && /^[[:space:]]+[^[:space:]]/    { print; next }
    { cap=0 }
  ' "$PREV_NOTE" 2>/dev/null || true)
fi

# ── GENERATE NEW NOTE FROM TEMPLATE ──────────────────────────────────────────
sed \
  -e "s|{{WEEK_LABEL}}|${WEEK_LABEL}|g" \
  -e "s|{{DATE_START}}|${DATE_START}|g" \
  -e "s|{{DATE_END}}|${DATE_END}|g" \
  -e "s|{{WEEK_NUM}}|${WEEK_NUM}|g" \
  -e "s|{{YEAR}}|${YEAR}|g" \
  -e "s|{{SPRINT}}|${SPRINT}|g" \
  -e "s|{{QUARTER}}|${QUARTER}|g" \
  -e "s|{{INIT_DATE}}|${INIT_DATE}|g" \
  "$TEMPLATE" > "$NOTE_FILE"

if [[ -n "$CARRIED" ]]; then
  {
    echo ""
    echo "## Carried From W${PW}"
    echo "$CARRIED"
  } >> "$NOTE_FILE"
fi

echo "[monday_init] Note created: $NOTE_FILE"

# ── WEEKEND-CHANGE DETECTION + MERGE ──────────────────────────────────────────
# Compare last week's note against the snapshot friday_process.sh saved at the
# Friday 16:30 close. Lines added over the weekend are merged forward into the
# new note (under '## Weekend Edits') and logged. No snapshot → log + skip.
WEEKEND_LOG="$LOG_DIR/weekend_edits.log"
SNAP="$WEEKLY_LOGS/.${PY}-W${PW}.fridayclose.snapshot.md"
wts() { date "+%Y-%m-%d %H:%M:%S"; }
if [[ -f "$PREV_NOTE" && -f "$SNAP" ]]; then
  if ! cmp -s "$SNAP" "$PREV_NOTE"; then
    # Added/changed lines = the '>' side of the diff (present now, not at close).
    ADDED=$(diff "$SNAP" "$PREV_NOTE" | sed -n 's/^> //p' || true)
    if [[ -n "$ADDED" ]]; then
      NLINES=$(printf '%s\n' "$ADDED" | grep -c . || true)
      {
        echo ""
        echo "## Weekend Edits (from W${PW})"
        echo "> Added to [[${PY}-W${PW}]] after Friday close — review and refile."
        echo '```text'
        printf '%s\n' "$ADDED"
        echo '```'
      } >> "$NOTE_FILE"
      echo "[$(wts)] W${PW}: ${NLINES} weekend line(s) merged into ${YEAR}-W${WEEK_NUM}.md" >> "$WEEKEND_LOG"
      echo "[monday_init] Weekend edits on W${PW} (${NLINES} line(s)) merged into the new note."
    else
      echo "[$(wts)] W${PW}: snapshot differs but no added lines — nothing merged" >> "$WEEKEND_LOG"
    fi
  fi
elif [[ -f "$PREV_NOTE" ]]; then
  echo "[$(wts)] W${PW}: no Friday-close baseline (snapshot missing) — detection skipped" >> "$WEEKEND_LOG"
fi

# ── UPDATE MASTER NOTE WEEKLY INDEX ───────────────────────────────────────────
if [[ ! -f "$MASTER" ]]; then
  echo "[monday_init] WARNING: Master Note not found at $MASTER — row NOT added." >&2
elif grep -Fq "| ${WIKILINK} |" "$MASTER"; then
  echo "[monday_init] Master Note already has a row for $WIKILINK — not duplicating."
elif ! grep -Fq "$INDEX_SENTINEL" "$MASTER"; then
  echo "[monday_init] WARNING: index sentinel not found in Master Note — row NOT added." >&2
else
  # Insert the row before the FIRST sentinel only (robust against duplicate sentinels).
  if awk -v row="$INDEX_ROW" -v sent="$INDEX_SENTINEL" '
        index($0, sent) && !done { print row; done=1 } { print }
      ' "$MASTER" > "$MASTER.tmp"; then
    mv "$MASTER.tmp" "$MASTER"
    echo "[monday_init] Master Note index row added for $WIKILINK."
  else
    rm -f "$MASTER.tmp"
    echo "[monday_init] WARNING: index update failed — row NOT added." >&2
  fi
fi
echo "[monday_init] Done — $(date)"
