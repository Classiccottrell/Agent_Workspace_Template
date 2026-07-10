#!/usr/bin/env bash
# config.sh - shared, relocatable configuration. Source from every script.
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="$WORKSPACE/Vault_Brain"
SOURCES="$VAULT/sources"
LOG_DIR="$WORKSPACE/System_Config/logs"
# launchd label namespace - overridable; defaults to the current user.
LABEL_PREFIX="${AGENT_WS_LABEL_PREFIX:-com.${USER}.vaultbrain}"
# launchd log redirects MUST live OUTSIDE the (TCC-protected) ~/Documents workspace,
# or launchd fails to open them at spawn -> EX_CONFIG (78); FDA on /bin/bash does NOT
# cover that open. ~/Library/Logs is safe. (Script logs still go to LOG_DIR above.)
LAUNCHD_LOG_DIR="$HOME/Library/Logs/$LABEL_PREFIX"
# KB_STRATEGY — set by bootstrap.sh. Both are Tier A (files ARE the store).
#   obsidian  - Obsidian app + Obsidian Web Clipper (default)
#   vscode    - VS Code + Foam + MarkSnip web clipper
KB_STRATEGY="${KB_STRATEGY:-obsidian}"
# ── Ingest configuration — set by bootstrap.sh, editable here anytime ─────────
# INGEST_SOURCES  - colon-separated dirs (relative to Vault_Brain/) scanned by
#                   daily_ingest.sh. Each dir keeps its own .ingested.log manifest.
# INGEST_PROVIDER - auto|claude|gemini. "auto" uses PATH detection below.
# INGEST_HOUR/MINUTE - daily launchd schedule (rendered into the plist on install).
# INGEST_MAX_BUDGET  - per-clip USD ceiling (claude only; gemini has no cost flag).
# INGEST_MAX_SECONDS - per-clip wall-clock watchdog (both providers).
# INGEST_PREFER_SAFE_PROVIDER - 1|0. When INGEST_PROVIDER=auto, prefer claude
#   over agy/gemini even if the latter are installed first on PATH. Reason:
#   run_agent.sh gates the claude branch with --allowedTools/--disallowedTools
#   (file tools only, Bash/Task/WebFetch denied); the agy/gemini branch only
#   has --sandbox (terminal restrictions), no per-tool allow/deny list — agy
#   ships no such flags at all, and gemini's --allowed-tools is a deprecated
#   auto-approve whitelist, not a deny-list. Set to 0, or set
#   INGEST_PROVIDER=gemini explicitly, to opt back into agy/gemini.
INGEST_SOURCES="${INGEST_SOURCES:-sources:Raw_Notes}"
INGEST_PROVIDER="${INGEST_PROVIDER:-auto}"
INGEST_PREFER_SAFE_PROVIDER="${INGEST_PREFER_SAFE_PROVIDER:-1}"
INGEST_HOUR="${INGEST_HOUR:-7}"
INGEST_MINUTE="${INGEST_MINUTE:-0}"
INGEST_MAX_BUDGET="${INGEST_MAX_BUDGET:-1.00}"
INGEST_MAX_SECONDS="${INGEST_MAX_SECONDS:-900}"
# Per-RUN ceiling: caps worst-case unattended spend at CLIPS_PER_RUN × MAX_BUDGET
# regardless of backlog size. Remaining clips carry to the next scheduled run.
INGEST_MAX_CLIPS_PER_RUN="${INGEST_MAX_CLIPS_PER_RUN:-10}"
# Clips larger than this are skipped with a WARN (huge clips burn the full
# watchdog+budget and can trip the quota-wall heuristic). 500 KB default.
INGEST_MAX_BYTES="${INGEST_MAX_BYTES:-512000}"
# Resolve the agent CLI (prioritizing Gemini/Antigravity, falling back to claude).
# The Gemini CLI ships as either `agy` (Antigravity) or `gemini`; accept both.
# NOTE: $CLAUDE holds whichever binary won — it is the GEMINI binary when
# AGENT_TYPE=gemini. Historical name; scripts branch on AGENT_TYPE, not the path.
if [[ "$INGEST_PROVIDER" == "claude" ]]; then
  CLAUDE="$(command -v claude || echo "$HOME/.local/bin/claude")"
  AGENT_TYPE="claude"
elif [[ "$INGEST_PROVIDER" == "auto" && "$INGEST_PREFER_SAFE_PROVIDER" == "1" ]] && command -v claude >/dev/null 2>&1; then
  CLAUDE="$(command -v claude || echo "$HOME/.local/bin/claude")"
  AGENT_TYPE="claude"
elif command -v agy >/dev/null 2>&1; then
  CLAUDE="$(command -v agy)"
  AGENT_TYPE="gemini"
elif [[ -x "$HOME/.local/bin/agy" ]]; then
  CLAUDE="$HOME/.local/bin/agy"
  AGENT_TYPE="gemini"
elif command -v gemini >/dev/null 2>&1; then
  CLAUDE="$(command -v gemini)"
  AGENT_TYPE="gemini"
else
  CLAUDE="$(command -v claude || echo "$HOME/.local/bin/claude")"
  AGENT_TYPE="claude"
fi
export AGENT_TYPE
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# ── Scheduler backend ─────────────────────────────────────────────────────────
# launchd (macOS) | cron (Linux with crontab) | none (anything else).
# The install_*.sh scripts branch on this; macOS behavior is unchanged.
case "$(uname -s)" in
  Darwin) SCHEDULER="launchd" ;;
  Linux)  if command -v crontab >/dev/null 2>&1; then SCHEDULER="cron"; else SCHEDULER="none"; fi ;;
  *)      SCHEDULER="none" ;;
esac

# install_cron_job <label> <cron-schedule> <script-path> — idempotent: replaces
# any prior entry carrying the same "# agent-ws:<label>" marker.
install_cron_job() {
  local label="$1" sched="$2" script="$3" marker="# agent-ws:${1}" tmp
  tmp="$(mktemp)"
  { crontab -l 2>/dev/null | grep -vF "$marker" || true
    echo "$sched cd $WORKSPACE && /bin/bash $script >> $LOG_DIR/${label}.cron.log 2>&1 $marker"
  } > "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  echo "  cron entry installed ($marker): $sched $script"
}

# rotate_log <file> [max_lines] — keep only the newest N lines (default 2000).
# Cheap cap so append-only logs and metrics never grow unbounded across years.
rotate_log() {
  local f="$1" max="${2:-2000}" tmp
  [ -f "$f" ] || return 0
  if [ "$(wc -l < "$f")" -gt "$max" ]; then
    tmp="$(mktemp)"
    tail -n "$max" "$f" > "$tmp" && mv "$tmp" "$f"
  fi
  return 0
}

# push_main — single gateway for pushing origin/main. Rebases with autostash
# first (snapshot and healthcheck both publish to main; rebase avoids the
# non-fast-forward races between them). Retries up to 2 more times (10s apart).
# Never exits — returns non-zero after the final failure; caller decides.
push_main() {
  local attempt=1 max=3
  while [ "$attempt" -le "$max" ]; do
    if git pull --rebase --autostash origin main && git push origin main; then
      echo "push_main: attempt $attempt succeeded"
      return 0
    fi
    echo "push_main: attempt $attempt failed"
    if [ "$attempt" -lt "$max" ]; then
      sleep 10
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

# remove_cron_job <label> — drop the marked entry, if any.
remove_cron_job() {
  local marker="# agent-ws:${1}" tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -vF "$marker" > "$tmp" || true
  crontab "$tmp" 2>/dev/null || true
  rm -f "$tmp"
}

# validate_config — sanity-check the sourced config. Never exits; only
# returns 0/1, so callers decide whether to abort. bash 3.2 safe (no arrays).
validate_config() {
  local var val
  for var in WORKSPACE VAULT SOURCES LOG_DIR LABEL_PREFIX CLAUDE AGENT_TYPE \
             SCHEDULER INGEST_SOURCES INGEST_PROVIDER INGEST_PREFER_SAFE_PROVIDER \
             INGEST_HOUR INGEST_MINUTE INGEST_MAX_BUDGET INGEST_MAX_SECONDS; do
    eval "val=\"\${$var:-}\""
    if [[ -z "$val" ]]; then
      echo "config.sh: $var is unset/empty" >&2
      return 1
    fi
  done

  [[ -d "$WORKSPACE" ]] || { echo "config.sh: WORKSPACE dir missing: $WORKSPACE" >&2; return 1; }
  [[ -d "$VAULT" ]] || { echo "config.sh: VAULT dir missing: $VAULT" >&2; return 1; }
  [[ -d "$SOURCES" ]] || echo "config.sh: warning: SOURCES dir missing: $SOURCES" >&2

  case "$INGEST_HOUR" in
    ''|*[!0-9]*) echo "config.sh: INGEST_HOUR is not an integer: $INGEST_HOUR" >&2; return 1 ;;
  esac
  if [[ "$INGEST_HOUR" -lt 0 || "$INGEST_HOUR" -gt 23 ]]; then
    echo "config.sh: INGEST_HOUR out of range 0-23: $INGEST_HOUR" >&2
    return 1
  fi

  case "$INGEST_MINUTE" in
    ''|*[!0-9]*) echo "config.sh: INGEST_MINUTE is not an integer: $INGEST_MINUTE" >&2; return 1 ;;
  esac
  if [[ "$INGEST_MINUTE" -lt 0 || "$INGEST_MINUTE" -gt 59 ]]; then
    echo "config.sh: INGEST_MINUTE out of range 0-59: $INGEST_MINUTE" >&2
    return 1
  fi

  case "$INGEST_PROVIDER" in
    auto|claude|gemini) : ;;
    *) echo "config.sh: INGEST_PROVIDER must be auto|claude|gemini: $INGEST_PROVIDER" >&2; return 1 ;;
  esac

  return 0
}
