# shellcheck shell=bash
# run_agent.sh — provider-agnostic headless agent invocation (sourced library, not standalone)
# Extracted from daily_ingest.sh / friday_process.sh's near-identical run_claude().
# Expects from the caller's environment: $CLAUDE $AGENT_TYPE $MAX_BUDGET $MAX_SECONDS $LOG $VAULT
#
# File tools only; Bash and other escape hatches denied; cwd = vault so the sandbox
# confines writes to the vault tree; budget + wall-clock watchdog bound the run.
run_agent() {
  local prompt="$1" pid wd rc
  cd "$VAULT"
  if [[ "${AGENT_TYPE:-}" == "gemini" ]]; then
    "$CLAUDE" -p "$prompt" \
          --sandbox \
          --dangerously-skip-permissions >> "$LOG" 2>&1 &
  else
    "$CLAUDE" -p "$prompt" \
          --allowedTools "Read,Write,Edit,Glob,Grep" \
          --disallowedTools "Bash,KillShell,Task,WebFetch,WebSearch,NotebookEdit" \
          --permission-mode acceptEdits \
          --max-budget-usd "$MAX_BUDGET" >> "$LOG" 2>&1 &
  fi
  pid=$!
  ( sleep "$MAX_SECONDS"; kill -TERM "$pid" 2>/dev/null ) &
  wd=$!
  disown "$wd" 2>/dev/null || true   # silence the "Terminated" job-control notice when we cancel the watchdog
  if wait "$pid"; then rc=0; else rc=$?; fi
  kill "$wd" 2>/dev/null || true
  return "$rc"
}
