#!/usr/bin/env bash
# config.sh - shared, relocatable configuration. Source from every script.
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="$WORKSPACE/Vault_Brain"
SOURCES="$VAULT/sources"
LOG_DIR="$WORKSPACE/System_Config/logs"
# launchd label namespace - overridable; defaults to the current user.
LABEL_PREFIX="${AGENT_WS_LABEL_PREFIX:-com.${USER}.vaultbrain}"
# Resolve the claude CLI from PATH, with a common fallback.
CLAUDE="$(command -v claude || echo "$HOME/.local/bin/claude")"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
