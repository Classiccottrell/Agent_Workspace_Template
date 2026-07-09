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
INGEST_SOURCES="${INGEST_SOURCES:-sources:Raw_Notes}"
INGEST_PROVIDER="${INGEST_PROVIDER:-auto}"
INGEST_HOUR="${INGEST_HOUR:-7}"
INGEST_MINUTE="${INGEST_MINUTE:-0}"
INGEST_MAX_BUDGET="${INGEST_MAX_BUDGET:-1.00}"
INGEST_MAX_SECONDS="${INGEST_MAX_SECONDS:-900}"
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
