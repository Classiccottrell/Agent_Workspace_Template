#!/usr/bin/env bash
set -euo pipefail

# migrate_vault.sh - vault schema versioning. Idempotent; run anytime.
# Sourced config.sh derives all paths at runtime, so this script is relocatable.

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=config.sh
source "$WORKSPACE/System_Config/config.sh"
validate_config || exit 1

TARGET_SCHEMA=1

# Read current schema version from marker file. Missing file = version 1.
schema_file="$VAULT/.vault-schema"
if [[ -f "$schema_file" ]]; then
  current=$(cat "$schema_file")
else
  current=1
  echo "$current" > "$schema_file"
fi

# Normalize to integer (strip whitespace).
current=$((current))

if [[ "$current" -eq "$TARGET_SCHEMA" ]]; then
  echo "vault schema v${current} — up to date"
  exit 0
elif [[ "$current" -lt "$TARGET_SCHEMA" ]]; then
  # Apply migrations in order: 1->2, 2->3, etc.
  case "$current" in
    # migrations land here as: 1->2) ...
    *)
      echo "error: unknown migration from schema v${current}" >&2
      exit 1
      ;;
  esac
elif [[ "$current" -gt "$TARGET_SCHEMA" ]]; then
  echo "error: vault is NEWER than this template — update the template first" >&2
  exit 1
fi
