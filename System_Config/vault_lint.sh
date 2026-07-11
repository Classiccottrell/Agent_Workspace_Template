#!/usr/bin/env bash
# vault_lint.sh — read-only vault health lint (Card #29). Schema: Vault_Brain/CLAUDE.md.
# Reports: (1) orphan wiki pages, (2) sources on disk missing from wiki/_index.md,
# (3) stale wiki pages (updated: >60d old), (4) wiki pages missing required
# frontmatter keys (title/type/updated). Never fixes anything. Always exits 0.
# bash 3.2 compatible (no associative arrays).

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

WIKI="$VAULT/wiki"
INDEX="$WIKI/_index.md"
LOG="$LOG_DIR/vault_lint.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG" 2000

NOW_EPOCH=$(date +%s)
STALE_DAYS=60

orphan_count=0; orphan_list=""
missing_index_count=0; missing_index_list=""
stale_count=0; stale_list=""
schema_count=0; schema_list=""

if [ -d "$WIKI" ]; then
  # ── (1) orphan wiki pages — basename never appears inside [[...]] in any OTHER page ──
  for f in "$WIKI"/*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f" .md)"
    [ "$b" = "_index" ] && continue
    hit=0
    for other in "$WIKI"/*.md; do
      [ -e "$other" ] || continue
      [ "$other" = "$f" ] && continue
      grep -qF "[[${b}" "$other" 2>/dev/null && { hit=1; break; }
    done
    if [ "$hit" -eq 0 ]; then
      orphan_count=$((orphan_count + 1))
      orphan_list="${orphan_list}${orphan_list:+, }${b}"
    fi
  done

  # ── (4) schema violations — first 10 lines missing title:/type:/updated: ──
  for f in "$WIKI"/*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f" .md)"
    [ "$b" = "_index" ] && continue
    head10="$(head -n 10 "$f")"
    miss=""
    printf '%s\n' "$head10" | grep -q '^title:' || miss="${miss}title "
    printf '%s\n' "$head10" | grep -q '^type:' || miss="${miss}type "
    printf '%s\n' "$head10" | grep -q '^updated:' || miss="${miss}updated "
    if [ -n "$miss" ]; then
      schema_count=$((schema_count + 1))
      schema_list="${schema_list}${schema_list:+, }${b} (missing: ${miss% })"
    fi
  done

  # ── (3) stale pages — updated: date >60 days old ──
  for f in "$WIKI"/*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f" .md)"
    [ "$b" = "_index" ] && continue
    upd="$(head -n 10 "$f" | grep '^updated:' | head -1 | sed 's/^updated:[[:space:]]*//')"
    if [ -z "$upd" ]; then
      continue  # already flagged by schema check
    fi
    upd_epoch="$(date -j -f '%Y-%m-%d' "$upd" +%s 2>/dev/null || true)"
    if [ -z "$upd_epoch" ]; then
      upd_epoch="$(date -d "$upd" +%s 2>/dev/null || true)"
    fi
    if [ -z "$upd_epoch" ]; then
      stale_count=$((stale_count + 1))
      stale_list="${stale_list}${stale_list:+, }${b} (unparseable date: ${upd})"
      continue
    fi
    age_days=$(( (NOW_EPOCH - upd_epoch) / 86400 ))
    if [ "$age_days" -gt "$STALE_DAYS" ]; then
      stale_count=$((stale_count + 1))
      stale_list="${stale_list}${stale_list:+, }${b} (${age_days}d)"
    fi
  done
fi

# ── (2) sources on disk missing from wiki/_index.md ──
if [ -s "$INDEX" ]; then
  OLD_IFS="$IFS"; IFS=':'
  SRC_DIRS=($INGEST_SOURCES)
  IFS="$OLD_IFS"
  for d in "${SRC_DIRS[@]}"; do
    [ -n "$d" ] || continue
    sdir="$VAULT/$d"
    [ -d "$sdir" ] || continue
    for f in "$sdir"/*.md; do
      [ -e "$f" ] || continue
      b="$(basename "$f")"
      case "$b" in _*|.*) continue ;; esac
      # _index.md wikilinks omit the .md extension ([[sources/slug]]); match on
      # the bare filename too so already-indexed sources aren't false-flagged.
      bare="${b%.md}"
      if grep -qF "$b" "$INDEX" 2>/dev/null || grep -qF "$bare" "$INDEX" 2>/dev/null; then
        :
      else
        missing_index_count=$((missing_index_count + 1))
        missing_index_list="${missing_index_list}${missing_index_list:+, }${d}/${b}"
      fi
    done
  done
else
  missing_index_list="(no _index.md — cannot check)"
fi

# ── report ──
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] vault_lint run"
  echo "  orphan wiki pages: ${orphan_count}${orphan_list:+ — ${orphan_list}}"
  echo "  sources missing from _index.md: ${missing_index_count}${missing_index_list:+ — ${missing_index_list}}"
  echo "  stale pages (>${STALE_DAYS}d): ${stale_count}${stale_list:+ — ${stale_list}}"
  echo "  schema violations: ${schema_count}${schema_list:+ — ${schema_list}}"
} | tee -a "$LOG"

exit 0
