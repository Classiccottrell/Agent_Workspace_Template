#!/usr/bin/env bash
# friday_archive.sh — Weekly Archive Processor
# Cron schedule: 0 18 * * 5  (Every Friday at 6:00 PM)
#
# Install cron entry (run from the workspace root so $PWD resolves the paths):
#   crontab -e
#   0 18 * * 5 /bin/bash "$PWD/System_Config/friday_archive.sh" >> "$PWD/System_Config/logs/friday_archive.log" 2>&1
# (Replace $PWD with the absolute path of your cloned workspace.)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── CONFIG ────────────────────────────────────────────────────────────────────
# WORKSPACE / VAULT / LOG_DIR come from config.sh.
WEEKLY_LOGS="$VAULT/weekly-logs"
ARCHIVE="$VAULT/archive"

# ── SETUP ─────────────────────────────────────────────────────────────────────
mkdir -p "$ARCHIVE" "$LOG_DIR"

# ── DATE CALCULATION ──────────────────────────────────────────────────────────
YEAR=$(date +%Y)
WEEK_NUM=$(date +%V)
ARCHIVE_DATE=$(date +%Y-%m-%d)

NOTE_FILE="$WEEKLY_LOGS/${YEAR}-W${WEEK_NUM}.md"

echo "[friday_archive] Processing W${WEEK_NUM} — ${ARCHIVE_DATE}"

# ── GUARD: confirm active note exists ────────────────────────────────────────
if [[ ! -f "$NOTE_FILE" ]]; then
  echo "[friday_archive] No active note found for W${WEEK_NUM}. Nothing to archive."
  exit 0
fi

# ── COMPILE OPEN ACTION ITEMS ────────────────────────────────────────────────
OPEN_ITEMS=$(grep -E "^\- \[ \]" "$NOTE_FILE" 2>/dev/null || echo "")
OPEN_COUNT=$(echo "$OPEN_ITEMS" | grep -c "^\- \[ \]" 2>/dev/null || echo "0")

echo "[friday_archive] Open action items found: $OPEN_COUNT"

# ── STAMP ARCHIVE DATE INTO NOTE ─────────────────────────────────────────────
if grep -q "{{ARCHIVE_DATE}}" "$NOTE_FILE" 2>/dev/null; then
  sed -i '' "s|{{ARCHIVE_DATE}}|${ARCHIVE_DATE}|g" "$NOTE_FILE"
fi

# Append archive footer
cat >> "$NOTE_FILE" <<EOF

---
## Archive Summary — ${ARCHIVE_DATE}
- **Week:** W${WEEK_NUM} ${YEAR}
- **Open items carried forward:** ${OPEN_COUNT}
- **Archived by:** friday_archive.sh

### Open Items (carry to next week)
${OPEN_ITEMS:-"None"}
EOF

# ── MOVE TO ARCHIVE ───────────────────────────────────────────────────────────
ARCHIVE_DEST="$ARCHIVE/${YEAR}-W${WEEK_NUM}.md"
mv "$NOTE_FILE" "$ARCHIVE_DEST"

echo "[friday_archive] Archived: $NOTE_FILE → $ARCHIVE_DEST"
echo "[friday_archive] Done — $(date)"
