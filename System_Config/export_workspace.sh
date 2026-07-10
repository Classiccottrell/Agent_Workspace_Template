#!/usr/bin/env bash
# export_workspace.sh — Anti-lock-in workspace export.
# Bundles the vault, projects, deliverables, and agent config into a single
# portable tar.gz so the workspace can be moved to another machine/provider.
#
# Usage:
#   ./export_workspace.sh [dest-dir]
#   (dest-dir defaults to ~/Desktop, falling back to $HOME if it doesn't exist)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
validate_config || { echo "export_workspace: invalid config, aborting" >&2; exit 1; }

# ── DEST ────────────────────────────────────────────────────────────────────
DEST="${1:-$HOME/Desktop}"
[[ -d "$DEST" ]] || DEST="$HOME"

ARCHIVE_NAME="agent-workspace-export-$(date +%Y-%m-%d).tar.gz"
ARCHIVE_PATH="$DEST/$ARCHIVE_NAME"

# ── INCLUDE LIST — only paths that actually exist (bash 3.2, no assoc arrays) ─
INCLUDES=()
for p in Vault_Brain Projects Final_Products System_Config/config.sh \
         .AGENT.MD CLAUDE.md .agents .claude/agents .claude/skills; do
  if [[ -e "$WORKSPACE/$p" ]]; then
    INCLUDES+=("$p")
  fi
done

if [[ "${#INCLUDES[@]}" -eq 0 ]]; then
  echo "export_workspace: nothing found to archive under $WORKSPACE" >&2
  exit 1
fi

# ── ARCHIVE ─────────────────────────────────────────────────────────────────
# --exclude flags must precede the path args (bsdtar on macOS ignores trailing
# excludes). Paths are relative (-C "$WORKSPACE") so the archive is portable.
tar -czf "$ARCHIVE_PATH" \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='*.log' \
  --exclude='System_Config/logs' \
  --exclude='.env*' \
  --exclude='.mcp.json' \
  --exclude='.DS_Store' \
  --exclude='*.key' \
  -C "$WORKSPACE" \
  "${INCLUDES[@]}"

SIZE="$(du -h "$ARCHIVE_PATH" | cut -f1)"
echo "export_workspace: archive created: $ARCHIVE_PATH ($SIZE)"
