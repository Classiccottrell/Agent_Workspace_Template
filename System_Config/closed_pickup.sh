#!/usr/bin/env bash
# closed_pickup.sh — Hourly backfill for Closed/INDEX.md.
#
# Scans Closed/ for project subfolders not yet registered in INDEX.md and
# appends a row with outcome "unspecified — needs review". Safe to re-run;
# already-registered projects are silently skipped.
#
# Usage:
#   bash System_Config/closed_pickup.sh          # real run
#   DRY_RUN=1 bash System_Config/closed_pickup.sh  # preview only, no changes
#
# Called automatically by closedpickup launchd agent (hourly + at login).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
  source "$SCRIPT_DIR/config.sh"
else
  WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

CLOSED="$WORKSPACE/Closed"
INDEX="$CLOSED/INDEX.md"
DRY_RUN="${DRY_RUN:-0}"
added=0

# ── Guard: Closed/ must exist ─────────────────────────────────────────────────
if [[ ! -d "$CLOSED" ]]; then
  echo "closed_pickup: Closed/ directory not found at $CLOSED — nothing to do." >&2
  exit 0
fi

# ── Guard: INDEX.md must exist (created at workspace init) ───────────────────
if [[ ! -f "$INDEX" ]]; then
  echo "closed_pickup: $INDEX not found — create it first (see Closed/.AGENT.MD)." >&2
  exit 1
fi

# ── Scan Closed/ for unregistered subfolders ─────────────────────────────────
while IFS= read -r dir; do
  name="$(basename "$dir")"
  # Skip hidden dirs and underscore-prefixed dirs (templates, meta)
  case "$name" in _*|.*) continue ;; esac

  # Membership check: is this name mentioned in INDEX.md?
  # NOTE: uses whole-file substring match; folders whose name is a substring
  # of existing prose are silently skipped. Acceptable for the automated
  # pickup case — the archivist can manually add ambiguous names.
  if grep -qF "$name" "$INDEX" 2>/dev/null; then
    continue
  fi

  # New folder: not yet in the registry
  closed_date="$(date '+%Y-%m-%d')"
  row="| $name | unspecified — needs review | $closed_date | auto-detected by closed_pickup.sh |"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] Would append row: $row"
  else
    echo "$row" >> "$INDEX"
    echo "closed_pickup: registered $name (outcome: unspecified — needs review)"
    added=$((added + 1))
  fi
done < <(find "$CLOSED" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if [[ "$added" -gt 0 ]]; then
  echo "closed_pickup: $added new project(s) registered in $INDEX"
  # Sync the Active Projects table to reflect the removal from Projects/
  if [[ -x "$SCRIPT_DIR/update_active_projects.sh" ]]; then
    bash "$SCRIPT_DIR/update_active_projects.sh" 2>/dev/null || true
  fi
elif [[ "$DRY_RUN" != "1" ]]; then
  echo "closed_pickup: nothing new in Closed/ — INDEX.md up to date."
fi
