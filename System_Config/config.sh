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
# Resolve the agent CLI (prioritizing Gemini/Antigravity, falling back to claude).
# The Gemini CLI ships as either `agy` (Antigravity) or `gemini`; accept both.
if command -v agy >/dev/null 2>&1; then
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
