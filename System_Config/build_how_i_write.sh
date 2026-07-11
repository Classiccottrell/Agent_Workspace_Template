#!/usr/bin/env bash
# build_how_i_write.sh — build the personal "how-i-write" writing-voice skill
# from a folder of your own writing samples, via one bounded headless call
# (same safety pattern as daily_ingest.sh: file tools only, Bash denied,
# budget/wall-clock capped where the CLI supports it, cwd confined).
#
# Writes ONLY to ~/.claude/skills/how-i-write/SKILL.md — OUTSIDE this repo.
# This template never ships personal writing-voice content (white-label rule).
#
#   Manual run:  bash System_Config/build_how_i_write.sh /path/to/samples
#   Via setup:   ./bootstrap.sh   (offers this as an interactive step)
#
# Never overwrites an existing SKILL.md — remove it first to rebuild.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
SYSCFG="$WORKSPACE/System_Config"

SAMPLES_DIR="${1:-}"
if [ -z "$SAMPLES_DIR" ] || [ ! -d "$SAMPLES_DIR" ]; then
  echo "Usage: bash System_Config/build_how_i_write.sh <path-to-writing-samples-folder>" >&2
  exit 1
fi
SAMPLES_DIR="$(cd "$SAMPLES_DIR" && pwd)"

SKILL_DIR="$HOME/.claude/skills/how-i-write"
SKILL_FILE="$SKILL_DIR/SKILL.md"
SCAFFOLD="$SYSCFG/how-i-write-template.md"

if [ -s "$SKILL_FILE" ]; then
  echo "[skip] $SKILL_FILE already exists — leaving it untouched."
  echo "       Remove it first (or edit it directly) if you want to rebuild."
  exit 0
fi
if [ ! -f "$SCAFFOLD" ]; then
  echo "[warn] Scaffold missing: $SCAFFOLD" >&2
  exit 1
fi

SAMPLE_COUNT=$(find "$SAMPLES_DIR" -maxdepth 3 -type f \( -name '*.md' -o -name '*.txt' \) 2>/dev/null | wc -l | tr -d ' ' || true)
SAMPLE_COUNT="${SAMPLE_COUNT:-0}"
if [ "$SAMPLE_COUNT" -eq 0 ]; then
  echo "[warn] No .md/.txt files found under $SAMPLES_DIR (searched 3 levels deep)." >&2
  exit 1
fi

mkdir -p "$SKILL_DIR"
cp "$SCAFFOLD" "$SKILL_FILE"

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/how_i_write_build.log"
ts()  { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }
log "build_how_i_write start: samples=$SAMPLES_DIR count=$SAMPLE_COUNT agent_type=${AGENT_TYPE:-claude}"

MAX_SECONDS="${MAX_SECONDS:-900}"
MAX_BUDGET="${MAX_BUDGET:-2.00}"    # USD ceiling — Claude path only; gemini/agy has no budget flag here (see daily_ingest.sh)

if [[ -r "$HOME/.config/anthropic/key" ]]; then
  export ANTHROPIC_API_KEY="$(cat "$HOME/.config/anthropic/key")"
fi

SCRATCH="$SKILL_DIR/.build-samples"
cleanup_scratch() { rm -rf "$SCRATCH"; }
trap cleanup_scratch EXIT
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
cp -R "$SAMPLES_DIR"/. "$SCRATCH"/
# Lock files only (not the directory itself) so the EXIT trap's rm -rf can still
# unlink them — mirrors daily_ingest.sh's "files read-only, dir stays writable" pattern.
find "$SCRATCH" -type f -exec chmod a-w {} + 2>/dev/null || true

PROMPT="You are running headlessly, ONE time, to fill in a personal writing-voice
skill from the user's own writing samples.

Samples (read-only copy, DO NOT write here): ./.build-samples/
Target file to edit: ./SKILL.md — already scaffolded. Fill in every
[FILL: ...] placeholder in the body AND the frontmatter 'description:'
placeholder (a one-line summary of when to use this skill). Keep the
frontmatter 'name: how-i-write' and the --- fences exactly as they are.

Steps:
1. Read every file under ./.build-samples/.
2. Identify recurring tone/register, sentence-length and structure patterns,
   vocabulary and word-choice habits, punctuation/formatting habits, and
   things this person's writing consistently avoids.
3. Edit ./SKILL.md in place, replacing each placeholder with what you found.
   Ground every claim in the samples — never invent a pattern that isn't
   actually present.
4. Delete the top HTML comment block (the SCAFFOLD NOTICE) once every
   placeholder below it is filled in.
5. Do not create or edit any other files."

cd "$SKILL_DIR"
set +e
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
pid=$!
( sleep "$MAX_SECONDS"; kill -TERM "$pid" 2>/dev/null ) &
wd=$!
disown "$wd" 2>/dev/null || true
if wait "$pid"; then rc=0; else rc=$?; fi
kill "$wd" 2>/dev/null || true
set -e

if [ "$rc" -eq 0 ]; then
  log "build_how_i_write done: OK"
else
  rm -f "$SKILL_FILE"
  log "build_how_i_write done: FAILED rc=$rc (may have timed out after ${MAX_SECONDS}s) — SKILL.md removed, retry any time"
fi
exit "$rc"
