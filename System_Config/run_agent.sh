# shellcheck shell=bash
# run_agent.sh — provider-agnostic headless agent invocation (sourced library, not standalone)
# Extracted from daily_ingest.sh / friday_process.sh's near-identical run_claude().
# Expects from the caller's environment: $CLAUDE $AGENT_TYPE $MAX_BUDGET $MAX_SECONDS $LOG $VAULT
#
# File tools only; Bash and other escape hatches denied; cwd = vault so the sandbox
# confines writes to the vault tree; budget + wall-clock watchdog bound the run.
agent_failure_kind() {
  if printf '%s' "$1" | grep -qiE "API key is invalid|Failed to authenticate|HTTP/1\.1 401|[^0-9]401[^0-9]"; then
    printf '%s\n' auth
  elif printf '%s' "$1" | grep -qiE "rate.?limit|quota|too many requests|HTTP/1\.1 429|[^0-9]429[^0-9]|budget.*(exceeded|reached)"; then
    printf '%s\n' quota
  else
    printf '%s\n' agent
  fi
}

run_agent() {
  local prompt="$1" pid wd rc model
  cd "$VAULT" || return 1
  if [[ -z "${CLAUDE:-}" || -z "${AGENT_TYPE:-}" ]]; then
    echo "${AGENT_RESOLUTION_ERROR:-agent target is unresolved}" >> "$LOG"
    return 127
  fi
  case "${AGENT_TYPE:-claude}" in
    gemini)
      if [[ -n "${AGENT_MODEL:-}" ]]; then
        "$CLAUDE" -p "$prompt" --model "$AGENT_MODEL" --sandbox --dangerously-skip-permissions >> "$LOG" 2>&1 &
      else
        "$CLAUDE" -p "$prompt" --sandbox --dangerously-skip-permissions >> "$LOG" 2>&1 &
      fi ;;
    codex)
      if [[ -n "${AGENT_MODEL:-}" ]]; then
        "$CLAUDE" exec --sandbox workspace-write --model "$AGENT_MODEL" "$prompt" >> "$LOG" 2>&1 &
      else
        "$CLAUDE" exec --sandbox workspace-write "$prompt" >> "$LOG" 2>&1 &
      fi ;;
    ollama)
      model="${AGENT_MODEL:-}"
      if [[ -z "$model" ]]; then
        model="$("$CLAUDE" list 2>>"$LOG" | awk 'NR==2{print $1; exit}')"
      fi
      if [[ -z "$model" ]]; then
        echo "ollama target needs OLLAMA_MODEL or at least one installed model (ollama pull <model>)" >> "$LOG"
        return 2
      fi
      "$CLAUDE" run "$model" "$prompt" >> "$LOG" 2>&1 & ;;
    *)
      if [[ -n "${AGENT_MODEL:-}" ]]; then
        "$CLAUDE" -p "$prompt" --model "$AGENT_MODEL" \
              --allowedTools "Read,Write,Edit,Glob,Grep" \
              --disallowedTools "Bash,KillShell,Task,WebFetch,WebSearch,NotebookEdit" \
              --permission-mode acceptEdits \
              --max-budget-usd "$MAX_BUDGET" >> "$LOG" 2>&1 &
      else
        "$CLAUDE" -p "$prompt" \
              --allowedTools "Read,Write,Edit,Glob,Grep" \
              --disallowedTools "Bash,KillShell,Task,WebFetch,WebSearch,NotebookEdit" \
              --permission-mode acceptEdits \
              --max-budget-usd "$MAX_BUDGET" >> "$LOG" 2>&1 &
      fi ;;
  esac
  pid=$!
  # TERM first; a CLI wedged in a network read can ignore TERM, so escalate to
  # KILL 20s later — otherwise `wait` blocks forever and the job never exits.
  ( sleep "$MAX_SECONDS"; kill -TERM "$pid" 2>/dev/null
    sleep 20;             kill -KILL "$pid" 2>/dev/null ) &
  wd=$!
  disown "$wd" 2>/dev/null || true   # silence the "Terminated" job-control notice when we cancel the watchdog
  if wait "$pid"; then rc=0; else rc=$?; fi
  kill "$wd" 2>/dev/null || true
  return "$rc"
}
