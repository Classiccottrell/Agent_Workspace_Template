#!/usr/bin/env bash
# closed_pickup.sh — Sweep Closed/ for project folders dropped in by hand
# (drag-and-drop path) with no agent involvement.
#
# For each immediate subfolder of Closed/ with no row yet in Closed/INDEX.md:
#   1. Best-effort scan for TODO/FIXME/XXX/placeholder markers. It cannot block a
#      move that already happened — it just annotates the row.
#   2. Append a registry row. Outcome defaults to "unspecified — needs review".
#   3. Run update_active_projects.sh so Projects/.AGENT.MD drops any row for a
#      folder that used to live under Projects/.
#
# Idempotent: the membership check runs before any append, so re-running never
# double-adds a row. Folders already indexed are left alone.
#
# REGISTRY SCHEMA — 5 columns. This MUST match Closed/INDEX.md's header exactly;
# a row with a different cell count makes the whole markdown table render wrong:
#   | Project | Folder | Outcome | Closed Date | Notes |
#
# Scheduled via launchd — see closedpickup.plist / closedpickup.plist.tmpl
#   Activate:  bash System_Config/install_closed_pickup.sh
#   Manual:    bash System_Config/closed_pickup.sh
#   Preview:   DRY_RUN=1 bash System_Config/closed_pickup.sh

set -uo pipefail   # deliberately NOT set -e: a scan failure on one folder must
                   # not abort the sweep over the remaining folders.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Relocatable: prefer the workspace's own config, else derive from script location.
# Never hardcode an absolute workspace path — this script ships in templates.
# shellcheck source=/dev/null
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
  source "$SCRIPT_DIR/config.sh"
else
  WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
: "${WORKSPACE:?closed_pickup: WORKSPACE unresolved — check config.sh}"
LOG_DIR="${LOG_DIR:-$WORKSPACE/System_Config/logs}"

# APPEND to PATH rather than replacing it: keeps whatever config.sh set, while
# guaranteeing the basics exist under launchd's minimal environment.
export PATH="${PATH}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

CLOSED="$WORKSPACE/Closed"
INDEX="$CLOSED/INDEX.md"
LOG="$LOG_DIR/closed_pickup.log"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$LOG_DIR"
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "closed_pickup start"

if [[ ! -d "$CLOSED" ]]; then
  log "Closed/ missing at $CLOSED — nothing to do"
  exit 0
fi
# exit 0, NOT 1: a freshly instantiated workspace legitimately has no registry
# yet, and a non-zero exit here makes launchd record the agent as failing.
if [[ ! -f "$INDEX" ]]; then
  log "Closed/INDEX.md missing — cannot backfill without the registry (see Closed/.AGENT.MD)"
  exit 0
fi

# Is this folder already registered? Field-split on '|' so no regex escaping is
# needed for folder names containing . + ( ) etc.
#
# Checks TWO cells, and both are necessary:
#   $2 Project — matched exactly. Rows written by this script put the folder name
#     here, but a human or the archivist may write a friendlier label instead
#     (e.g. Project "AI Mineral System (legacy)" for folder "AI Mineral system").
#   $3 Folder  — the machine-written cell, always [`<folder>/`](<encoded>/). We
#     look for the backticked "`<name>/`" needle, which is the folder name
#     verbatim. This is what catches the friendly-label rows above.
#
# Why the needle includes the trailing slash and both backticks: it keeps the
# substring bug fixed. Folder "foo" looks for "`foo/`", which does NOT appear in
# "`foobar/`" (after "foo" comes "b", not "/"). A bare substring search over the
# whole file — the old behaviour — wrongly skipped "foo" whenever "foobar" or a
# passing mention in another row's Notes existed.
already_indexed() {
  awk -F'|' -v n="$1" '
    BEGIN { needle = "`" n "/`" }
    NF >= 3 {
      p = $2; gsub(/^[ \t]+|[ \t]+$/, "", p)
      if (p == n) { found = 1; exit }
      if (index($3, needle) > 0) { found = 1; exit }
    }
    END { exit !found }
  ' "$INDEX"
}

TODAY="$(date +%Y-%m-%d)"
added=0
would_add=0

# Process substitution keeps the loop in the current shell, so the counters below
# survive the loop (a `find | while` pipeline would lose them to a subshell).
while IFS= read -r dir; do
  [[ -d "$dir" ]] || continue
  name="$(basename "$dir")"
  case "$name" in _*|.*) continue ;; esac

  already_indexed "$name" && continue

  hit=0
  if grep -rlIE 'TODO|FIXME|XXX|placeholder' "$dir" \
      --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist \
      >/dev/null 2>&1; then
    hit=1
  fi

  outcome="unspecified — needs review"
  note="Backfilled by closed_pickup.sh — folder appeared under Closed/ with no registry entry (manual move, no agent dispatch)."
  if [[ "$hit" -eq 1 ]]; then
    note="${note} Contains TODO/FIXME/XXX/placeholder marker(s) — review before treating as final."
  fi

  # Percent-encode spaces so the markdown folder link resolves.
  link_name="$(printf '%s' "$name" | sed 's/ /%20/g')"
  row="$(printf '| %s | [`%s/`](%s/) | %s | %s | %s |' \
    "$name" "$name" "$link_name" "$outcome" "$TODAY" "$note")"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] would append: $row"
    would_add=$((would_add + 1))
    continue
  fi

  printf '%s\n' "$row" >> "$INDEX"
  added=$((added + 1))
  log "backfilled registry row for: $name (todo-hit=$hit)"
done < <(find "$CLOSED" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if [[ "$DRY_RUN" == "1" ]]; then
  log "dry run — ${would_add} row(s) would be added, nothing written"
  exit 0
fi

if [[ "$added" -gt 0 ]]; then
  log "added $added row(s) — syncing Active Projects table"
  if [[ -x "$SCRIPT_DIR/update_active_projects.sh" ]]; then
    bash "$SCRIPT_DIR/update_active_projects.sh" >> "$LOG" 2>&1 \
      || log "WARN: update_active_projects.sh exited non-zero"
  else
    log "WARN: $SCRIPT_DIR/update_active_projects.sh missing or not executable — Active Projects table not synced"
  fi
else
  log "nothing to do — all Closed/ folders already indexed"
fi

log "closed_pickup done"
exit 0
