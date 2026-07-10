#!/usr/bin/env bash
# daily_ingest.sh — Vault_Brain daily note ingestion
# Scans each dir in INGEST_SOURCES (config.sh; vault-relative, colon-separated —
# e.g. "sources:Raw_Notes") for new .md notes and runs the agent CLI headlessly to
# wikify them (create/update wiki pages, update _index.md, log to weekly note).
# Processes ONE clip per agent call so a partial failure only retries that clip.
#
# Scheduled via launchd — see dailyingest.plist.tmpl (label com.<username>.vaultbrain.dailyingest)
#   Activate:    bash System_Config/install_daily_ingest.sh
#   Manual run:  bash System_Config/daily_ingest.sh
#   Preview:     DRY_RUN=1 bash System_Config/daily_ingest.sh   (lists clips, no agent call)
#
# Unattended auth: if ~/.config/anthropic/key (mode 0600) exists it is used as
# ANTHROPIC_API_KEY. Otherwise the run relies on the Claude Code login keychain,
# which only works inside an active GUI login session.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── CONFIG ────────────────────────────────────────────────────────────────────
# WORKSPACE / VAULT / LOG_DIR / CLAUDE / INGEST_* come from config.sh.
LOG="$LOG_DIR/daily_ingest.log"
MAX_SECONDS="${MAX_SECONDS:-$INGEST_MAX_SECONDS}"   # per-clip wall-clock watchdog (both providers)
MAX_BUDGET="${MAX_BUDGET:-$INGEST_MAX_BUDGET}"      # per-clip USD ceiling (claude only —
                                                    # ponytail: gemini has no cost flag; its only
                                                    # ceiling is the MAX_SECONDS watchdog)

# Optional non-interactive auth for unattended runs (avoids keychain prompts).
if [[ -r "$HOME/.config/anthropic/key" ]]; then
  export ANTHROPIC_API_KEY="$(cat "$HOME/.config/anthropic/key")"
fi

# ── SETUP / LOGGING ───────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "daily_ingest start (sources: ${INGEST_SOURCES})"

# ── DATES ─────────────────────────────────────────────────────────────────────
# ISO week-year (%G) MUST pair with ISO week (%V); calendar year (%Y) diverges at year edges.
YEAR=$(date +%G)
WEEK=$(date +%V)
TODAY=$(date +%Y-%m-%d)
WEEKLY_NOTE="weekly-logs/${YEAR}-W${WEEK}.md"

if [[ -z "${ANTHROPIC_API_KEY:-}" && "${DRY_RUN:-0}" != "1" ]]; then
  log "note: ANTHROPIC_API_KEY unset — relying on login keychain (active GUI session only)"
fi

# ── SOURCES IMMUTABILITY BACKSTOP ─────────────────────────────────────────────
# Lock note files read-only for the duration so no tool path can mutate them; always restore.
restore_sources() {
  local d old_ifs="$IFS"
  IFS=':'
  for d in $INGEST_SOURCES; do
    [[ -n "$d" ]] && chmod u+w "$VAULT/$d"/*.md 2>/dev/null || true
  done
  IFS="$old_ifs"
}
trap restore_sources EXIT

# ── BOUNDED HEADLESS AGENT CALL ───────────────────────────────────────────────
source "$(dirname "${BASH_SOURCE[0]}")/run_agent.sh"

# ── PER-DIRECTORY SCAN + INGEST ───────────────────────────────────────────────
# Each source dir keeps its OWN manifest (<dir>/.ingested.log) so the legacy
# sources/ manifest keeps working and basenames can't collide across dirs.
total_ingested=0
total_new=0

process_dir() {
  local rel_dir="$1"
  local src_dir="$VAULT/$rel_dir"
  local manifest="$src_dir/.ingested.log"

  # Guard: the dir must exist (catches unmounted / renamed / synced-away vault).
  if [[ ! -d "$src_dir" ]]; then
    log "WARN: source dir missing, skipping: $src_dir (vault unmounted or dir renamed?)"
    return 0
  fi
  touch "$manifest"

  # ── MANIFEST MIGRATION (self-healing; bash 3.2 — no associative arrays) ─────
  # Dedup by CONTENT (sha256), not just filename: a byte-identical clip saved under
  # a different name (e.g. the Web Clipper's unsanitized {{title}}) must not trigger
  # a second paid ingest. Manifest format: "<sha256>\t<basename>". Older manifests
  # stored bare "<basename>"; back-fill a hash for any legacy line whose source file
  # still exists (lines for vanished files are kept name-only — can't rehash them).
  local MIG migrated=0 line mh
  MIG="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    case "$line" in
      *"$(printf '\t')"*) printf '%s\n' "$line" ;;            # already hashed
      *)
        if [[ -f "$src_dir/$line" ]]; then
          mh="$(shasum -a 256 "$src_dir/$line" | awk '{print $1}')"
          printf '%s\t%s\n' "$mh" "$line"; migrated=$((migrated + 1))
        else
          printf '%s\n' "$line"                               # source gone — keep name-only
        fi ;;
    esac
  done < "$manifest" > "$MIG"
  mv "$MIG" "$manifest"
  [[ $migrated -gt 0 ]] && log "manifest($rel_dir): back-filled $migrated legacy entr(ies) with content hash"

  # Lookups against the manifest ($NF = basename for both formats; $1 = hash when present).
  name_seen() { awk -F'\t' -v n="$1" '$NF==n{f=1} END{exit !f}' "$manifest"; }
  hash_seen() { awk -F'\t' -v h="$1" 'NF>=2 && $1==h{f=1} END{exit !f}' "$manifest"; }

  # ── FIND NEW NOTES (content-hash dedup) ──────────────────────────────────────
  # Capture find's exit status explicitly — process substitution would swallow it.
  local NEW=() FOUND f base h
  FOUND="$(mktemp)"
  if ! find "$src_dir" -maxdepth 1 -type f -name "*.md" > "$FOUND" 2>>"$LOG"; then
    log "FATAL: find failed scanning $src_dir — skipping dir"
    rm -f "$FOUND"
    return 0
  fi
  # Note subfolders we do NOT scan, so clips filed there aren't silently invisible.
  local sub_count
  sub_count="$(find "$src_dir" -mindepth 2 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$sub_count" -gt 0 ]] && log "WARN: $sub_count .md file(s) in subfolders of $rel_dir/ are not scanned — add the subfolder to INGEST_SOURCES in config.sh to ingest them"

  while IFS= read -r f; do
    base="$(basename "$f")"
    case "$base" in
      _*|.*) continue ;;   # skip templates and dotfiles
    esac
    name_seen "$base" && continue                            # already ingested by name
    h="$(shasum -a 256 "$f" | awk '{print $1}')"
    if hash_seen "$h"; then
      log "skip (duplicate content of an already-ingested clip): $rel_dir/$base [${h:0:12}]"
      printf '%s\t%s\n' "$h" "$base" >> "$manifest"          # record so it is not rescanned
      continue
    fi
    NEW+=("$base")
  done < "$FOUND"
  rm -f "$FOUND"

  if [[ ${#NEW[@]} -eq 0 ]]; then
    log "no new clips in $rel_dir/"
    return 0
  fi
  log "new clips in $rel_dir/ (${#NEW[@]}): ${NEW[*]}"
  total_new=$((total_new + ${#NEW[@]}))

  # ── DRY RUN ──────────────────────────────────────────────────────────────────
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "── DRY RUN — would ingest ${#NEW[@]} clip(s) from $rel_dir/, one agent call each ──"
    printf '%s\n' "${NEW[@]}"
    echo "── weekly note: ${WEEKLY_NOTE} ──"
    echo "── per-clip flags: --allowedTools Read,Write,Edit,Glob,Grep --disallowedTools Bash,... --permission-mode acceptEdits --max-budget-usd ${MAX_BUDGET} (watchdog ${MAX_SECONDS}s) ──"
    log "dry run — no agent call for $rel_dir/"
    return 0
  fi

  # Lock this dir's notes read-only while the agent runs (restored by EXIT trap).
  chmod a-w "$src_dir"/*.md 2>/dev/null || true

  # ── INGEST EACH CLIP INDEPENDENTLY ───────────────────────────────────────────
  local clip src_link PROMPT rc
  for clip in "${NEW[@]}"; do
    src_link="${rel_dir}/${clip%.md}"
    PROMPT="You are running headlessly to ingest ONE note into the Vault_Brain knowledge wiki.
First read CLAUDE.md for the wiki schema and conventions.

Note to process: ${rel_dir}/${clip}

Steps:
1. Read ${rel_dir}/${clip}. Do NOT edit it — files in ${rel_dir}/ are immutable.
2. Identify the primary entity (project, person, technology, org, or concept) and create or update its page in wiki/ using the page format in CLAUDE.md.
   - IDEMPOTENCY: first check whether the target wiki page already contains a link to [[${src_link}]]. If it does, this note was already ingested — make NO changes and stop.
   - If the page exists: APPEND new facts and add '- [[${src_link}]]' under its Sources section. Never rewrite or delete existing content.
   - If new: create it with the exact frontmatter + sections, including the [[${src_link}]] link.
   - Cross-link aggressively to existing wiki pages with [[wikilinks]].
3. Update wiki/_index.md to list any new wiki page and the new source (skip if already listed).
4. Ensure ${WEEKLY_NOTE} exists. If not, create it from Weekly_Note_Template.md (WEEK_NUM=${WEEK}, YEAR=${YEAR}).
5. Append exactly one line to its '## Claude Sessions' section: '- ${TODAY}: ingested ${clip} -> [[wiki/<page-slug>]]'.

Constraints: create-or-append only; never overwrite a page wholesale; never delete anything; stay within this vault."

    log "ingesting: $rel_dir/$clip"
    if run_agent "$PROMPT"; then
      # Verify the agent actually wikified this note before recording it. A no-op
      # (timeout, declined, empty result) also exits 0; without this check the note
      # would be marked done forever and never retried. A real ingest always links
      # [[<dir>/<slug>]] from a wiki page or _index.md.
      if grep -rqF "[[${src_link}]]" "$VAULT/wiki/" 2>/dev/null; then
        h="$(shasum -a 256 "$src_dir/$clip" | awk '{print $1}')"
        printf '%s\t%s\n' "$h" "$clip" >> "$manifest"
        total_ingested=$((total_ingested + 1))
        log "OK: $rel_dir/$clip"
      else
        log "NO-OP (exit 0 but no wiki link to ${src_link}): $rel_dir/$clip — NOT recorded, will retry next run"
      fi
    else
      rc=$?
      log "FAILED (rc=${rc}; may have timed out after ${MAX_SECONDS}s): $rel_dir/$clip — NOT recorded, will retry next run"
    fi
  done
}

# Split on ':' without mangling globals (bash 3.2 safe).
OLD_IFS="$IFS"; IFS=':'
DIRS=($INGEST_SOURCES)
IFS="$OLD_IFS"
for d in "${DIRS[@]}"; do
  [[ -n "$d" ]] && process_dir "$d"
done

restore_sources
log "daily_ingest done — ingested ${total_ingested}/${total_new} clip(s)"
