#!/usr/bin/env bash
# test.sh — template self-tests. Run before pushing / in CI.
#
#   bash System_Config/test.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSCFG="$ROOT/System_Config"

FAIL=0

run() {
  local desc="$1"; shift
  echo "→ $desc"
  if "$@"; then
    echo "  [ok] $desc"
  else
    echo "  [FAIL] $desc"
    FAIL=1
  fi
}

# ---------------------------------------------------------------------------
# 1. Syntax check every owned script.
# ---------------------------------------------------------------------------
SCRIPTS="$ROOT/bootstrap.sh"
for f in "$SYSCFG"/*.sh; do
  [ -e "$f" ] || continue
  SCRIPTS="$SCRIPTS $f"
done

for f in $SCRIPTS; do
  run "bash -n $(basename "$f")" bash -n "$f"
done

# ---------------------------------------------------------------------------
# 2. shellcheck --severity=error, if available.
# ---------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  for f in $SCRIPTS; do
    run "shellcheck --severity=error $(basename "$f")" shellcheck --severity=error "$f"
  done
else
  echo "[skip] shellcheck not installed (brew install shellcheck)"
fi

# ---------------------------------------------------------------------------
# 3. Rules drift gate.
# ---------------------------------------------------------------------------
run "sync_rules.sh --check" bash "$SYSCFG/sync_rules.sh" --check

# ---------------------------------------------------------------------------
# 3b. Ordered provider resolver (Bash 3.2-compatible, no real CLI required).
# ---------------------------------------------------------------------------
run "ordered provider resolver" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT
  mkdir -p "$tmp/.local/bin"
  printf "#!/bin/sh\nexit 0\n" > "$tmp/.local/bin/claude"
  printf "#!/bin/sh\nexit 0\n" > "$tmp/.local/bin/codex"
  chmod +x "$tmp/.local/bin/claude" "$tmp/.local/bin/codex"
  HOME="$tmp"; INGEST_TARGETS="claude:codex"; CODEX_MODEL="test-model"
  export HOME INGEST_TARGETS CODEX_MODEL
  source "$1/config.sh"
  [[ "$AGENT_TYPE" == claude && "$AGENT_TARGET_INDEX" -eq 1 ]]
  advance_agent_target
  [[ "$AGENT_TYPE" == codex && "$AGENT_MODEL" == test-model && "$AGENT_TARGET_INDEX" -eq 2 ]]
' _ "$SYSCFG"

# Legacy mode must ignore an ambient AGENT_MODEL and preserve the old argv.
run "legacy provider argv ignores ambient model" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT
  mkdir -p "$tmp/.local/bin"
  printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" \"\$@\" > \"\$CAPTURE\"" > "$tmp/.local/bin/claude"
  chmod +x "$tmp/.local/bin/claude"
  HOME="$tmp"; PATH="$tmp/.local/bin:$PATH"; INGEST_TARGETS=""; INGEST_PROVIDER="claude"; AGENT_MODEL="ambient-model"
  CAPTURE="$tmp/argv"; LOG="$tmp/log"; MAX_SECONDS=2; MAX_BUDGET=1.00
  export HOME INGEST_TARGETS INGEST_PROVIDER AGENT_MODEL CAPTURE
  source "$1/config.sh"
  [[ -z "${AGENT_MODEL+x}" ]]
  source "$1/run_agent.sh"
  run_agent "legacy prompt"
  ! grep -q -- "--model" "$CAPTURE"
  printf "%s\n" -p "legacy prompt" --allowedTools Read,Write,Edit,Glob,Grep \
    --disallowedTools Bash,KillShell,Task,WebFetch,WebSearch,NotebookEdit \
    --permission-mode acceptEdits --max-budget-usd 1.00 > "$tmp/expected"
  cmp "$tmp/expected" "$CAPTURE"
' _ "$SYSCFG"

run "Gemini legacy argv" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT; mkdir -p "$tmp/.local/bin"
  printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" \"\$@\" > \"\$CAPTURE\"" > "$tmp/.local/bin/agy"
  chmod +x "$tmp/.local/bin/agy"
  HOME="$tmp"; PATH="$tmp/.local/bin:$PATH"; INGEST_TARGETS=""; INGEST_PROVIDER=auto
  CAPTURE="$tmp/argv"; LOG="$tmp/log"; MAX_SECONDS=2; MAX_BUDGET=1; export HOME PATH INGEST_TARGETS INGEST_PROVIDER CAPTURE
  source "$1/config.sh"; source "$1/run_agent.sh"; run_agent prompt
  printf "%s\n" -p prompt --sandbox --dangerously-skip-permissions > "$tmp/expected"
  cmp "$tmp/expected" "$CAPTURE"
' _ "$SYSCFG"

run "Claude and Gemini configured model argv" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT; mkdir -p "$tmp/.local/bin"
  for cli in claude gemini; do
    printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" \"\$@\" > \"\$CAPTURE\"" > "$tmp/.local/bin/$cli"
    chmod +x "$tmp/.local/bin/$cli"
  done
  HOME="$tmp"; PATH="$tmp/.local/bin:/usr/bin:/bin"; INGEST_TARGETS=claude:gemini
  CLAUDE_MODEL=claude-test; GEMINI_MODEL=gemini-test
  CAPTURE="$tmp/argv"; LOG="$tmp/log"; MAX_SECONDS=2; MAX_BUDGET=1
  export HOME PATH INGEST_TARGETS CLAUDE_MODEL GEMINI_MODEL CAPTURE
  source "$1/config.sh"; source "$1/run_agent.sh"
  run_agent prompt
  printf "%s\n" -p prompt --model claude-test --allowedTools Read,Write,Edit,Glob,Grep \
    --disallowedTools Bash,KillShell,Task,WebFetch,WebSearch,NotebookEdit \
    --permission-mode acceptEdits --max-budget-usd 1 > "$tmp/expected"
  cmp "$tmp/expected" "$CAPTURE"
  advance_agent_target; run_agent prompt
  printf "%s\n" -p prompt --model gemini-test --sandbox --dangerously-skip-permissions > "$tmp/expected"
  cmp "$tmp/expected" "$CAPTURE"
' _ "$SYSCFG"

run "Codex and Ollama argv" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT; mkdir -p "$tmp/.local/bin"
  printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" \"\$@\" > \"\$CAPTURE\"" > "$tmp/.local/bin/codex"
  printf "#!/bin/sh\nexit 0\n" > "$tmp/.local/bin/ollama"
  chmod +x "$tmp/.local/bin/codex" "$tmp/.local/bin/ollama"
  HOME="$tmp"; INGEST_TARGETS=codex:ollama; CODEX_MODEL=codex-test; OLLAMA_MODEL=ollama-test
  CAPTURE="$tmp/argv"; LOG="$tmp/log"; MAX_SECONDS=2; MAX_BUDGET=1
  export HOME INGEST_TARGETS CODEX_MODEL OLLAMA_MODEL CAPTURE; source "$1/config.sh"; source "$1/run_agent.sh"
  run_agent prompt
  printf "%s\n" exec --sandbox workspace-write --model codex-test prompt > "$tmp/expected"; cmp "$tmp/expected" "$CAPTURE"
  advance_agent_target; run_agent prompt
  printf "%s\n" exec --oss --local-provider ollama --model ollama-test --sandbox workspace-write prompt > "$tmp/expected"; cmp "$tmp/expected" "$CAPTURE"
' _ "$SYSCFG"

run "configured targets fail closed" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT
  HOME="$tmp"; PATH=/usr/bin:/bin; INGEST_TARGETS=ollama; export HOME PATH INGEST_TARGETS
  source "$1/config.sh"
  PATH=/usr/bin:/bin
  resolve_agent_target ollama && exit 1 || true
  [[ -z "$CLAUDE" && -z "$AGENT_TYPE" && "$AGENT_RESOLUTION_ERROR" == *ollama* ]]
' _ "$SYSCFG"

run "rate classification and handoff resume" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT; mkdir -p "$tmp/.local/bin"
  for cli in claude codex; do printf "#!/bin/sh\nexit 0\n" > "$tmp/.local/bin/$cli"; chmod +x "$tmp/.local/bin/$cli"; done
  HOME="$tmp"; INGEST_TARGETS=claude:codex; export HOME INGEST_TARGETS
  source "$1/config.sh"; source "$1/run_agent.sh"
  large="$(printf "%070000d" 0)"
  [[ "$(agent_failure_kind "${large}
API Error: HTTP/1.1 429 Too Many Requests")" == quota ]]
  [[ "$(agent_failure_kind "Error: 401 API key is invalid")" == auth ]]
  [[ "$(agent_failure_kind "content says rate limit and 429")" == agent ]]
  now=$(date +%s)
  provider_state_timestamp_valid "$now" "$now" 86400
  ! provider_state_timestamp_valid "$((now + 60))" "$now" 86400
  ! provider_state_timestamp_valid "$((now - 86401))" "$now" 86400
  advance_agent_target
  state="$tmp/state"; state_tmp="$tmp/state.tmp"
  printf "%s\t%s\n" "$INGEST_TARGETS" "$AGENT_TARGET_INDEX" > "$state_tmp"; mv "$state_tmp" "$state"
  AGENT_TARGET_INDEX=1; IFS="$(printf "\t")" read -r targets index < "$state"
  [[ "$targets" == "$INGEST_TARGETS" ]]; select_agent_target_index "$index"
  [[ "$AGENT_TYPE" == codex && "$AGENT_TARGET_INDEX" -eq 2 ]]
' _ "$SYSCFG"

# Piped invocation is bounded and must not enter interactive setup.
run "bounded piped bootstrap help" bash -c '
  set -euo pipefail
  out=$(mktemp)
  trap "rm -f \"$out\"" EXIT
  "$1/bootstrap.sh" --help </dev/null >"$out" &
  pid=$!
  ( sleep 5; kill -TERM "$pid" 2>/dev/null ) &
  watchdog=$!
  wait "$pid"; rc=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  [[ "$rc" -eq 0 ]] && grep -q -- "--check" "$out"
' _ "$ROOT"

# ---------------------------------------------------------------------------
# 3c. Health notification dedup and Closed registry matching regressions.
# ---------------------------------------------------------------------------
HEALTHCHECK_LIB_ONLY=1 source "$SYSCFG/healthcheck.sh"
TMP_TEST="$(mktemp -d)"
printf '| Project | Folder | Outcome | Closed Date | Notes |\n| foobar | [`foobar/`](foobar/) | ok | 2026-01-01 | mentions foo |\n' > "$TMP_TEST/index.md"
rejects_collision() { ! closed_registry_has foo "$1"; }
failed_unacknowledged() { ! persist_notification_signature "$1" abc false && [ ! -e "$1" ]; }
successful_acknowledged() { persist_notification_signature "$1" abc true && [ "$(cat "$1")" = abc ]; }
run "closed registry rejects name collisions" rejects_collision "$TMP_TEST/index.md"
run "closed registry exact project match" closed_registry_has foobar "$TMP_TEST/index.md"
run "failed notification is not acknowledged" failed_unacknowledged "$TMP_TEST/state"
run "successful notification is acknowledged" successful_acknowledged "$TMP_TEST/state"
rm -rf "$TMP_TEST"

# ---------------------------------------------------------------------------
# 4. Vault schema gate.
# ---------------------------------------------------------------------------
run "migrate_vault.sh" bash "$SYSCFG/migrate_vault.sh"

# ---------------------------------------------------------------------------
# 5. Python compiles; JSON parses. (Catches broken hooks/generators before users do.)
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  for p in "$ROOT/.claude/hooks/readme-currency-check.py" "$ROOT/.codex/hooks/readme-currency-check.py" "$SYSCFG/gen_site.py"; do
    [ -f "$p" ] || continue
    run "py_compile $(basename "$p")" python3 -m py_compile "$p"
  done
  for j in "$ROOT/.claude/settings.json" "$ROOT/.codex/hooks.json" "$ROOT/.mcp.json.example"; do
    [ -f "$j" ] || continue
    run "json valid $(basename "$j")" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$j"
  done
  if python3 -c 'import tomllib' >/dev/null 2>&1; then
    for t in "$ROOT/.codex/config.toml" "$ROOT/.codex/agents"/*.toml; do
      run "toml valid $(basename "$t")" python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1],"rb"))' "$t"
    done
  else
    echo "[skip] tomllib unavailable (Python 3.11+ required for TOML validation)"
  fi
else
  echo "[skip] python3 not installed — py_compile/JSON checks skipped"
fi

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: all checks passed"
else
  echo "FAIL: one or more checks failed"
fi
exit "$FAIL"
