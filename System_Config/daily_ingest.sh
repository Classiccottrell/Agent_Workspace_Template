#!/usr/bin/env bash
# daily_ingest.sh — Vault_Brain daily clip ingestion
# Scans Vault_Brain/sources/ for new web clips and runs Claude headlessly to
# wikify them (create/update wiki pages, update _index.md, log to weekly note).
# Processes ONE clip per Claude call so a partial failure only retries that clip.
#
# Scheduled via launchd — see dailyingest.plist.tmpl (label com.<username>.vaultbrain.dailyingest)
#   Activate:    bash System_Config/install_daily_ingest.sh
#   Manual run:  bash System_Config/daily_ingest.sh
#   Preview:     DRY_RUN=1 bash System_Config/daily_ingest.sh   (lists clips, no Claude call)
#
# Unattended auth: if ~/.config/anthropic/key (mode 0600) exists it is used as
# ANTHROPIC_API_KEY. Otherwise the run relies on the Claude Code login keychain,
# which only works inside an active GUI login session.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── CONFIG ────────────────────────────────────────────────────────────────────
# WORKSPACE / VAULT / SOURCES / LOG_DIR / CLAUDE come from config.sh.
MANIFEST="$SOURCES/.ingested.log"
LOG="$LOG_DIR/daily_ingest.log"
MAX_SECONDS="${MAX_SECONDS:-900}"   # per-clip wall-clock watchdog
MAX_BUDGET="${MAX_BUDGET:-1.00}"    # per-clip USD cost ceiling

# Optional non-interactive auth for unattended runs (avoids keychain prompts).
if [[ -r "$HOME/.config/anthropic/key" ]]; then
  export ANTHROPIC_API_KEY="$(cat "$HOME/.config/anthropic/key")"
fi

# ── SETUP / LOGGING ───────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "daily_ingest start"

# Guard: the vault sources dir must exist (catches unmounted / renamed / synced-away vault).
if [[ ! -d "$SOURCES" ]]; then
  log "FATAL: sources dir missing or not a directory: $SOURCES — aborting (vault unmounted?)"
  exit 1
fi
touch "$MANIFEST"

# ── MANIFEST MIGRATION (self-healing; bash 3.2 — no associative arrays) ───────
# Dedup by CONTENT (sha256), not just filename: a byte-identical clip saved under
# a different name (e.g. the Web Clipper's unsanitized {{title}}) must not trigger
# a second paid ingest. Manifest format: "<sha256>\t<basename>". Older manifests
# stored bare "<basename>"; back-fill a hash for any legacy line whose source file
# still exists (lines for vanished files are kept name-only — can't rehash them).
MIG="$(mktemp)"
migrated=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  case "$line" in
    *"$(printf '\t')"*) printf '%s\n' "$line" ;;            # already hashed
    *)
      if [[ -f "$SOURCES/$line" ]]; then
        mh="$(shasum -a 256 "$SOURCES/$line" | awk '{print $1}')"
        printf '%s\t%s\n' "$mh" "$line"; migrated=$((migrated + 1))
      else
        printf '%s\n' "$line"                               # source gone — keep name-only
      fi ;;
  esac
done < "$MANIFEST" > "$MIG"
mv "$MIG" "$MANIFEST"
[[ $migrated -gt 0 ]] && log "manifest: back-filled $migrated legacy entr(ies) with content hash"

# Lookups against the manifest ($NF = basename for both formats; $1 = hash when present).
name_seen() { awk -F'\t' -v n="$1" '$NF==n{f=1} END{exit !f}' "$MANIFEST"; }
hash_seen() { awk -F'\t' -v h="$1" 'NF>=2 && $1==h{f=1} END{exit !f}' "$MANIFEST"; }

# ── FIND NEW CLIPS (content-hash dedup) ──────────────────────────────────────
# Capture find's exit status explicitly — process substitution would swallow it.
NEW=()
FOUND="$(mktemp)"
if ! find "$SOURCES" -maxdepth 1 -type f -name "*.md" > "$FOUND" 2>>"$LOG"; then
  log "FATAL: find failed scanning $SOURCES — aborting"
  rm -f "$FOUND"
  exit 1
fi
while IFS= read -r f; do
  base="$(basename "$f")"
  case "$base" in
    _*|.*) continue ;;   # skip templates and dotfiles
  esac
  name_seen "$base" && continue                            # already ingested by name
  h="$(shasum -a 256 "$f" | awk '{print $1}')"
  if hash_seen "$h"; then
    log "skip (duplicate content of an already-ingested clip): $base [${h:0:12}]"
    printf '%s\t%s\n' "$h" "$base" >> "$MANIFEST"          # record so it is not rescanned
    continue
  fi
  NEW+=("$base")
done < "$FOUND"
rm -f "$FOUND"

if [[ ${#NEW[@]} -eq 0 ]]; then
  log "no new clips — exiting"
  exit 0
fi
log "new clips (${#NEW[@]}): ${NEW[*]}"

# ── DATES ─────────────────────────────────────────────────────────────────────
# ISO week-year (%G) MUST pair with ISO week (%V); calendar year (%Y) diverges at year edges.
YEAR=$(date +%G)
WEEK=$(date +%V)
TODAY=$(date +%Y-%m-%d)
WEEKLY_NOTE="weekly-logs/${YEAR}-W${WEEK}.md"

# ── DRY RUN ───────────────────────────────────────────────────────────────────
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "── DRY RUN — would ingest ${#NEW[@]} clip(s), one Claude call each ──"
  printf '%s\n' "${NEW[@]}"
  echo "── weekly note: ${WEEKLY_NOTE} ──"
  echo "── per-clip flags: --allowedTools Read,Write,Edit,Glob,Grep --disallowedTools Bash,... --permission-mode acceptEdits --max-budget-usd ${MAX_BUDGET} (watchdog ${MAX_SECONDS}s) ──"
  log "dry run — no Claude call"
  exit 0
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  log "note: ANTHROPIC_API_KEY unset — relying on login keychain (active GUI session only)"
fi

# ── SOURCES IMMUTABILITY BACKSTOP ─────────────────────────────────────────────
# Lock clip files read-only for the duration so no tool path can mutate them; always restore.
restore_sources() { chmod u+w "$SOURCES"/*.md 2>/dev/null || true; }
trap restore_sources EXIT
chmod a-w "$SOURCES"/*.md 2>/dev/null || true

# ── BOUNDED HEADLESS CLAUDE CALL ──────────────────────────────────────────────
# File tools only; Bash and other escape hatches denied; cwd = vault so the sandbox
# confines writes to the vault tree; budget + wall-clock watchdog bound the run.
run_claude() {
  local prompt="$1" pid wd rc
  cd "$VAULT"
  "$CLAUDE" -p "$prompt" \
        --allowedTools "Read,Write,Edit,Glob,Grep" \
        --disallowedTools "Bash,KillShell,Task,WebFetch,WebSearch,NotebookEdit" \
        --permission-mode acceptEdits \
        --max-budget-usd "$MAX_BUDGET" >> "$LOG" 2>&1 &
  pid=$!
  ( sleep "$MAX_SECONDS"; kill -TERM "$pid" 2>/dev/null ) &
  wd=$!
  disown "$wd" 2>/dev/null || true   # silence the "Terminated" job-control notice when we cancel the watchdog
  if wait "$pid"; then rc=0; else rc=$?; fi
  kill "$wd" 2>/dev/null || true
  return "$rc"
}

# ── INGEST EACH CLIP INDEPENDENTLY ────────────────────────────────────────────
ingested=0
for clip in "${NEW[@]}"; do
  src_link="${clip%.md}"
  PROMPT="You are running headlessly to ingest ONE web clip into the Vault_Brain knowledge wiki.
First read CLAUDE.md for the wiki schema and conventions.

Clip to process: sources/${clip}

Steps:
1. Read sources/${clip}. Do NOT edit it — files in sources/ are immutable.
2. Identify the primary entity (project, person, technology, org, or concept) and create or update its page in wiki/ using the page format in CLAUDE.md.
   - IDEMPOTENCY: first check whether the target wiki page already contains a link to [[sources/${src_link}]]. If it does, this clip was already ingested — make NO changes and stop.
   - If the page exists: APPEND new facts and add '- [[sources/${src_link}]]' under its Sources section. Never rewrite or delete existing content.
   - If new: create it with the exact frontmatter + sections, including the [[sources/${src_link}]] link.
   - Cross-link aggressively to existing wiki pages with [[wikilinks]].
3. Update wiki/_index.md to list any new wiki page and the new source (skip if already listed).
4. Ensure ${WEEKLY_NOTE} exists. If not, create it from Weekly_Note_Template.md (WEEK_NUM=${WEEK}, YEAR=${YEAR}).
5. Append exactly one line to its '## Claude Sessions' section: '- ${TODAY}: ingested ${clip} -> [[wiki/<page-slug>]]'.

Constraints: create-or-append only; never overwrite a page wholesale; never delete anything; stay within this vault."

  log "ingesting: $clip"
  if run_claude "$PROMPT"; then
    h="$(shasum -a 256 "$SOURCES/$clip" | awk '{print $1}')"
    printf '%s\t%s\n' "$h" "$clip" >> "$MANIFEST"
    ingested=$((ingested + 1))
    log "OK: $clip"
  else
    rc=$?
    log "FAILED (rc=${rc}; may have timed out after ${MAX_SECONDS}s): $clip — NOT recorded, will retry next run"
  fi
done

restore_sources
log "daily_ingest done — ingested ${ingested}/${#NEW[@]} clip(s)"
