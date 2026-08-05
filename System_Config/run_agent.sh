# shellcheck shell=bash
# run_agent.sh — provider-agnostic headless agent invocation (sourced library, not standalone)
# Extracted from daily_ingest.sh / friday_process.sh's near-identical run_claude().
# Expects from the caller's environment: $CLAUDE $AGENT_TYPE $MAX_BUDGET $MAX_SECONDS $LOG $VAULT
#
# cwd = vault and workspace-write confine Codex/Ollama writes to the vault tree.
# Codex exposes no per-run USD budget or tool allow-list; MAX_SECONDS is its hard bound.
agent_failure_kind() {
  if grep -qiE '^[[:space:]]*(Error|API Error):.*(API key is invalid|Failed to authenticate|HTTP/1\.1 401|[^0-9]401([^0-9]|$))' <<<"$1"; then
    printf '%s\n' auth
  elif grep -qiE '^[[:space:]]*(Error|API Error):.*(rate.?limit|quota|too many requests|HTTP/1\.1 429|[^0-9]429([^0-9]|$)|budget.*(exceeded|reached))' <<<"$1"; then
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
      if [[ -n "${AGENT_MODEL:-}" ]]; then
        "$CLAUDE" exec --oss --local-provider ollama --model "$AGENT_MODEL" --sandbox workspace-write "$prompt" >> "$LOG" 2>&1 &
      else
        "$CLAUDE" exec --oss --local-provider ollama --sandbox workspace-write "$prompt" >> "$LOG" 2>&1 &
      fi ;;
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
