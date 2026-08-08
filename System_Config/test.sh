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
# 3d. notify.sh delivery contract. Stubbed binaries, so this is deterministic on
#     any platform and raises no real banner: exit 0 only when a notification was
#     raised or deliberately suppressed, exit 1 when delivery was attempted and
#     failed — with the dedup signature left unwritten so the alert retries.
# ---------------------------------------------------------------------------
NOTIFY_TMP="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' > "$NOTIFY_TMP/ok"; chmod +x "$NOTIFY_TMP/ok"
NOTIFY_SELFTEST_STATE="$SYSCFG/logs/.notify_events/selftest"
rm -f "$NOTIFY_SELFTEST_STATE"

# Webhook stubs (NOTIFY_CURL_BIN test seam) — never touch the network.
printf '#!/bin/sh\ncat >/dev/null\nprintf "200"\n' > "$NOTIFY_TMP/curl_ok"
printf '#!/bin/sh\ncat >/dev/null\nprintf "500"\n' > "$NOTIFY_TMP/curl_fail"
printf '%s\n' '#!/bin/sh' 'cat >/dev/null' 'prev=""' 'for a in "$@"; do' \
  '  [ "$prev" = "-d" ] && printf "%s" "$a" > "$CAPTURE_PAYLOAD"' '  prev="$a"' 'done' \
  'printf "200"' > "$NOTIFY_TMP/curl_capture"
printf '#!/bin/sh\ntouch "%s/curl_called"\nprintf "200"\n' "$NOTIFY_TMP" > "$NOTIFY_TMP/curl_marks_called"
chmod +x "$NOTIFY_TMP/curl_ok" "$NOTIFY_TMP/curl_fail" "$NOTIFY_TMP/curl_capture" "$NOTIFY_TMP/curl_marks_called"

# NOTIFY_ENV_FILE=/dev/null on all four: guarantees these run hermetically
# regardless of what's really in this machine's .notify.env. GCHAT_WEBHOOK_URL=""
# alone can't do this — notify.sh's caller-value-wins restore only fires on a
# non-empty override (`[[ -n "$_pre_gchat" ]]`), so an explicitly-blanked empty
# string is indistinguishable from "caller didn't set it" and the file's real
# value would still win.
notify_delivers() {
  NOTIFY_ENV_FILE=/dev/null NOTIFY_OSASCRIPT="$NOTIFY_TMP/ok" bash "$SYSCFG/notify.sh" \
    --event selftest --dedup sig-a "selftest" "body" && [ -s "$NOTIFY_SELFTEST_STATE" ]
}
notify_dedupes() {
  NOTIFY_ENV_FILE=/dev/null NOTIFY_OSASCRIPT="$NOTIFY_TMP/ok" bash "$SYSCFG/notify.sh" \
    --event selftest --dedup sig-a "selftest" "body"
}
notify_failure_retries() {
  rm -f "$NOTIFY_SELFTEST_STATE"
  ! NOTIFY_ENV_FILE=/dev/null \
      NOTIFY_OSASCRIPT="$NOTIFY_TMP/absent" NOTIFY_SEND_BIN="$NOTIFY_TMP/absent" \
      bash "$SYSCFG/notify.sh" --event selftest --dedup sig-b "selftest" "body" \
    && [ ! -e "$NOTIFY_SELFTEST_STATE" ]
}
notify_disabled_is_quiet() {
  NOTIFY_ENV_FILE=/dev/null NOTIFY_ENABLED=0 \
    NOTIFY_OSASCRIPT="$NOTIFY_TMP/absent" NOTIFY_SEND_BIN="$NOTIFY_TMP/absent" \
    bash "$SYSCFG/notify.sh" --event selftest "selftest" "body"
}
run "notify.sh delivers and records the dedup signature" notify_delivers
run "notify.sh dedupes an unchanged signature" notify_dedupes
run "notify.sh exits 1 on failed delivery, leaving no dedup state" notify_failure_retries
run "notify.sh honours NOTIFY_ENABLED=0 over .notify.env" notify_disabled_is_quiet

# ── Opt-in webhook delivery (additive; local delivery stays the default above) ─
notify_webhook_delivers_when_local_fails() {
  NOTIFY_OSASCRIPT="$NOTIFY_TMP/absent" NOTIFY_SEND_BIN="$NOTIFY_TMP/absent" \
    NOTIFY_CURL_BIN="$NOTIFY_TMP/curl_ok" GCHAT_WEBHOOK_URL="https://example.invalid/webhook" \
    bash "$SYSCFG/notify.sh" --event selftest --dedup sig-c "selftest" "body" \
    && [ -s "$NOTIFY_SELFTEST_STATE" ]
}
notify_all_channels_failing_retries() {
  rm -f "$NOTIFY_SELFTEST_STATE"
  ! NOTIFY_OSASCRIPT="$NOTIFY_TMP/absent" NOTIFY_SEND_BIN="$NOTIFY_TMP/absent" \
      NOTIFY_CURL_BIN="$NOTIFY_TMP/curl_fail" GCHAT_WEBHOOK_URL="https://example.invalid/webhook" \
      bash "$SYSCFG/notify.sh" --event selftest --dedup sig-d "selftest" "body" \
    && [ ! -e "$NOTIFY_SELFTEST_STATE" ]
}
notify_webhook_payload_is_valid_json() {
  command -v python3 >/dev/null 2>&1 || return 0   # skip silently, mirrors other python3-gated checks
  payload="$NOTIFY_TMP/payload.json"; rm -f "$payload"
  CAPTURE_PAYLOAD="$payload" NOTIFY_OSASCRIPT="$NOTIFY_TMP/absent" NOTIFY_SEND_BIN="$NOTIFY_TMP/absent" \
    NOTIFY_CURL_BIN="$NOTIFY_TMP/curl_capture" GCHAT_WEBHOOK_URL="https://example.invalid/webhook" \
    bash "$SYSCFG/notify.sh" --event selftest --dedup sig-e "$(printf 'multi\nline title')" \
      "$(printf 'line one\nline two')" >/dev/null 2>&1
  [ -s "$payload" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$payload"
}
notify_no_webhook_configured_never_calls_curl() {
  rm -f "$NOTIFY_TMP/curl_called"
  # NOTIFY_ENV_FILE=/dev/null: this test's premise is "no webhook is
  # configured," which it can't otherwise guarantee — it sets neither webhook
  # var, so a real .notify.env on this machine would supply one uncontested.
  NOTIFY_ENV_FILE=/dev/null NOTIFY_OSASCRIPT="$NOTIFY_TMP/ok" NOTIFY_CURL_BIN="$NOTIFY_TMP/curl_marks_called" \
    bash "$SYSCFG/notify.sh" --event selftest --dedup sig-f "selftest" "body" >/dev/null 2>&1
  [ ! -e "$NOTIFY_TMP/curl_called" ]
}
run "notify.sh webhook delivers when local delivery fails" notify_webhook_delivers_when_local_fails
run "notify.sh exits 1 when local and webhook both fail" notify_all_channels_failing_retries
run "notify.sh webhook payload is valid JSON (multi-line title/body)" notify_webhook_payload_is_valid_json
run "notify.sh never invokes curl with no webhook configured" notify_no_webhook_configured_never_calls_curl

rm -rf "$NOTIFY_TMP"; rm -f "$NOTIFY_SELFTEST_STATE"

# ---------------------------------------------------------------------------
# 3e. decisions_sweep.sh — DRY_RUN path and the '## Decisions'-slice hash-diff
#     no-op detector (decisions_slice), which must ignore edits elsewhere in
#     the weekly note and react only to edits inside the Decisions section.
# ---------------------------------------------------------------------------
DECISIONS_SWEEP_LIB_ONLY=1 source "$SYSCFG/decisions_sweep.sh"

DS_FIXTURE="$(mktemp)"
cat > "$DS_FIXTURE" <<'EOF'
## Claude Sessions
- 2026-08-01: did something

## Decisions
| Decision | Rationale | Date |
|---|---|---|
| Chose X | because Y | 2026-08-01 |

## Sources
- none
EOF
DS_HASH_BEFORE="$(decisions_slice "$DS_FIXTURE" | shasum -a 256 | awk '{print $1}')"

ds_hash_ignores_changes_outside_decisions() {
  local f="$DS_FIXTURE.outside" h2
  cp "$DS_FIXTURE" "$f"
  sed -i.bak 's/did something/did something else/' "$f" && rm -f "$f.bak"
  h2="$(decisions_slice "$f" | shasum -a 256 | awk '{print $1}')"
  rm -f "$f"
  [ "$h2" = "$DS_HASH_BEFORE" ]
}
ds_hash_reacts_to_changes_inside_decisions() {
  local f="$DS_FIXTURE.inside" h2
  cp "$DS_FIXTURE" "$f"
  sed -i.bak 's/Chose X/Chose Z/' "$f" && rm -f "$f.bak"
  h2="$(decisions_slice "$f" | shasum -a 256 | awk '{print $1}')"
  rm -f "$f"
  [ "$h2" != "$DS_HASH_BEFORE" ]
}
run "decisions_slice ignores edits outside ## Decisions" ds_hash_ignores_changes_outside_decisions
run "decisions_slice reacts to edits inside ## Decisions" ds_hash_reacts_to_changes_inside_decisions
rm -f "$DS_FIXTURE"

DS_WEEK_TAG="$(date +%G)-W$(date +%V)"
DS_NOTE="$ROOT/Vault_Brain/weekly-logs/${DS_WEEK_TAG}.md"
DS_CREATED_NOTE=0
if [ ! -f "$DS_NOTE" ]; then
  mkdir -p "$(dirname "$DS_NOTE")"
  printf '# %s\n\n## Claude Sessions\n-\n\n## Decisions\n\n| Decision | Rationale | Date |\n|---|---|---|\n' \
    "$DS_WEEK_TAG" > "$DS_NOTE"
  DS_CREATED_NOTE=1
fi
ds_dry_run_preview() {
  # Captured, not piped directly into grep -q: a direct pipe lets grep -q exit
  # the instant it matches the DRY RUN block's first echo, closing the pipe
  # while decisions_sweep.sh is still writing its 2nd/3rd line — the SIGPIPE
  # that kills it then outranks grep's success under this file's `pipefail`,
  # failing a check that actually passed.
  local out
  out="$(DRY_RUN=1 bash "$SYSCFG/decisions_sweep.sh" 2>&1)"
  printf '%s' "$out" | grep -q "DRY RUN"
}
run "decisions_sweep.sh DRY_RUN preview" ds_dry_run_preview
[ "$DS_CREATED_NOTE" -eq 1 ] && rm -f "$DS_NOTE"

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
