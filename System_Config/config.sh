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
# INGEST_PROVIDER - legacy auto|claude|gemini selector.
# INGEST_TARGETS  - optional ordered, colon-separated claude|gemini|codex|ollama.
#                   Empty preserves legacy provider resolution byte-for-behavior.
# *_MODEL         - optional model override; empty uses that CLI's default.
# INGEST_HOUR/MINUTE - daily launchd schedule (rendered into the plist on install).
# INGEST_MAX_BUDGET  - per-clip USD ceiling (claude only; other CLIs have no cost flag).
# INGEST_MAX_SECONDS - per-clip wall-clock watchdog (both providers).
INGEST_SOURCES="${INGEST_SOURCES:-sources:Raw_Notes}"
INGEST_PROVIDER="${INGEST_PROVIDER:-auto}"
INGEST_TARGETS="${INGEST_TARGETS:-}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
GEMINI_MODEL="${GEMINI_MODEL:-}"
CODEX_MODEL="${CODEX_MODEL:-}"
OLLAMA_MODEL="${OLLAMA_MODEL:-}"
# INGEST_IGNORE_KEYFILE=1 skips ~/.config/anthropic/key and relies on the
# login keychain instead — use if that file ever holds a stale/revoked key.
INGEST_IGNORE_KEYFILE="${INGEST_IGNORE_KEYFILE:-0}"
INGEST_HOUR="${INGEST_HOUR:-7}"
INGEST_MINUTE="${INGEST_MINUTE:-0}"
INGEST_MAX_BUDGET="${INGEST_MAX_BUDGET:-1.00}"
INGEST_MAX_SECONDS="${INGEST_MAX_SECONDS:-900}"
# Per-RUN ceiling: caps worst-case unattended spend at CLIPS_PER_RUN × MAX_BUDGET
# regardless of backlog size. Remaining clips carry to the next scheduled run.
INGEST_MAX_CLIPS_PER_RUN="${INGEST_MAX_CLIPS_PER_RUN:-10}"
# Resolve the agent CLI (prioritizing Gemini/Antigravity, falling back to claude).
# The Gemini CLI ships as either `agy` (Antigravity) or `gemini`; accept both.
# NOTE: $CLAUDE holds whichever binary won — it is the GEMINI binary when
# AGENT_TYPE=gemini. Historical name; scripts branch on AGENT_TYPE, not the path.
if [[ "$INGEST_PROVIDER" == "claude" ]]; then
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

# resolve_agent_target <target> — updates legacy CLAUDE/AGENT_TYPE plus model.
# Gemini accepts either the Antigravity `agy` name or upstream `gemini`.
resolve_agent_target() {
  local target="$1" bin=""
  case "$target" in
    claude) bin="$(command -v claude || true)"; AGENT_MODEL="$CLAUDE_MODEL" ;;
    gemini)
      bin="$(command -v agy || command -v gemini || true)"
      AGENT_MODEL="$GEMINI_MODEL"
      ;;
    codex)  bin="$(command -v codex || true)"; AGENT_MODEL="$CODEX_MODEL" ;;
    ollama)
      command -v ollama >/dev/null 2>&1 || return 1
      bin="$(command -v codex || true)"
      AGENT_MODEL="$OLLAMA_MODEL"
      ;;
    *) return 1 ;;
  esac
  [[ -n "$bin" ]] || return 1
  CLAUDE="$bin"
  AGENT_TYPE="$target"
  export CLAUDE AGENT_TYPE AGENT_MODEL
}

AGENT_TARGET_INDEX=1
if [[ -n "$INGEST_TARGETS" ]]; then
  OLD_TARGET_IFS="$IFS"; IFS=':'; AGENT_TARGET_LIST=($INGEST_TARGETS); IFS="$OLD_TARGET_IFS"
  while [[ "$AGENT_TARGET_INDEX" -le "${#AGENT_TARGET_LIST[@]}" ]]; do
    resolve_agent_target "${AGENT_TARGET_LIST[$((AGENT_TARGET_INDEX - 1))]}" && break
    AGENT_TARGET_INDEX=$((AGENT_TARGET_INDEX + 1))
  done
  if [[ "$AGENT_TARGET_INDEX" -gt "${#AGENT_TARGET_LIST[@]}" ]]; then
    CLAUDE=""
    AGENT_TYPE=""
    AGENT_MODEL=""
    AGENT_RESOLUTION_ERROR="none of the configured INGEST_TARGETS are installed: $INGEST_TARGETS"
  fi
else
  # Legacy mode never accepted a model override. Ignore ambient shell state so
  # the original Claude/Gemini argv remains unchanged.
  unset AGENT_MODEL
fi

# Advance only after a rate/quota failure. Callers checkpoint completed work
# before invoking this, and never replay the failed task on the next provider.
advance_agent_target() {
  [[ -n "$INGEST_TARGETS" ]] || return 1
  AGENT_TARGET_INDEX=$((AGENT_TARGET_INDEX + 1))
  while [[ "$AGENT_TARGET_INDEX" -le "${#AGENT_TARGET_LIST[@]}" ]]; do
    resolve_agent_target "${AGENT_TARGET_LIST[$((AGENT_TARGET_INDEX - 1))]}" && return 0
    AGENT_TARGET_INDEX=$((AGENT_TARGET_INDEX + 1))
  done
  return 1
}

select_agent_target_index() {
  local wanted="$1"
  [[ -n "$INGEST_TARGETS" ]] || return 1
  case "$wanted" in ''|*[!0-9]*|0) return 1 ;; esac
  [[ "$wanted" -le "${#AGENT_TARGET_LIST[@]}" ]] || return 1
  AGENT_TARGET_INDEX="$wanted"
  while [[ "$AGENT_TARGET_INDEX" -le "${#AGENT_TARGET_LIST[@]}" ]]; do
    resolve_agent_target "${AGENT_TARGET_LIST[$((AGENT_TARGET_INDEX - 1))]}" && return 0
    AGENT_TARGET_INDEX=$((AGENT_TARGET_INDEX + 1))
  done
  return 1
}

provider_state_timestamp_valid() {
  local saved_at="$1" now="$2" ttl="$3" age
  case "$saved_at" in ''|*[!0-9]*) return 1 ;; esac
  age=$((now - saved_at))
  [[ "$age" -ge 0 && "$age" -le "$ttl" ]]
}

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

# remove_cron_job <label> — drop the marked entry, if any.
remove_cron_job() {
  local marker="# agent-ws:${1}" tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -vF "$marker" > "$tmp" || true
  crontab "$tmp" 2>/dev/null || true
  rm -f "$tmp"
}

# validate_config_base — config required by every script, including non-agent installers.
validate_config_base() {
  local var val
  for var in WORKSPACE VAULT SOURCES LOG_DIR LABEL_PREFIX SCHEDULER INGEST_SOURCES \
             INGEST_PROVIDER INGEST_HOUR INGEST_MINUTE INGEST_MAX_BUDGET INGEST_MAX_SECONDS; do
    eval "val=\"\${$var:-}\""
    if [[ -z "$val" ]]; then echo "config.sh: $var is unset/empty" >&2; return 1; fi
  done
  [[ -d "$WORKSPACE" ]] || { echo "config.sh: WORKSPACE dir missing: $WORKSPACE" >&2; return 1; }
  [[ -d "$VAULT" ]] || { echo "config.sh: VAULT dir missing: $VAULT" >&2; return 1; }
}

validate_agent_config() {
  validate_config_base || return 1
  if [[ -z "${CLAUDE:-}" || -z "${AGENT_TYPE:-}" ]]; then
    echo "config.sh: ${AGENT_RESOLUTION_ERROR:-agent target is unresolved}" >&2
    return 1
  fi
}

# validate_config — backward-compatible base validation. Never exits; only
# returns 0/1, so callers decide whether to abort. bash 3.2 safe (no arrays).
validate_config() {
  local var val
  for var in WORKSPACE VAULT SOURCES LOG_DIR LABEL_PREFIX \
             SCHEDULER INGEST_SOURCES INGEST_PROVIDER INGEST_HOUR INGEST_MINUTE \
             INGEST_MAX_BUDGET INGEST_MAX_SECONDS; do
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

  local target old_ifs="$IFS"
  IFS=':'
  for target in $INGEST_TARGETS; do
    case "$target" in claude|gemini|codex|ollama) : ;;
      *) echo "config.sh: bad INGEST_TARGETS entry: $target" >&2; IFS="$old_ifs"; return 1 ;;
    esac
  done
  IFS="$old_ifs"

  return 0
}
