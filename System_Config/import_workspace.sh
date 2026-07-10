#!/usr/bin/env bash
# import_workspace.sh — Anti-lock-in workspace import (counterpart to
# export_workspace.sh). Extracts an exported archive into a fresh directory.
#
# Usage:
#   ./import_workspace.sh <archive> [target-dir]
#   (target-dir defaults to the current directory)

set -euo pipefail

ARCHIVE="${1:-}"
TARGET="${2:-$PWD}"

if [[ -z "$ARCHIVE" ]]; then
  echo "usage: import_workspace.sh <archive> [target-dir]" >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "import_workspace: archive not found: $ARCHIVE" >&2
  exit 1
fi

# ── GUARD: never merge-overwrite an existing workspace ─────────────────────
if [[ -d "$TARGET/Vault_Brain" ]]; then
  echo "import_workspace: refusing to import — $TARGET already contains a Vault_Brain/." >&2
  echo "import_workspace: import into an empty directory instead, e.g.:" >&2
  echo "  mkdir -p ~/new-workspace && ./import_workspace.sh \"$ARCHIVE\" ~/new-workspace" >&2
  exit 1
fi

# ── SANITY CHECK: archive must actually be a workspace export ──────────────
if ! tar -tzf "$ARCHIVE" | grep -q '^Vault_Brain/'; then
  echo "import_workspace: archive does not contain Vault_Brain/, aborting: $ARCHIVE" >&2
  exit 1
fi

mkdir -p "$TARGET"
tar -xzf "$ARCHIVE" -C "$TARGET"

echo "import_workspace: extracted $ARCHIVE -> $TARGET"
echo "import_workspace: next step — run ./bootstrap.sh in the new workspace clone/template to rewire automation."
