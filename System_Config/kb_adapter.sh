#!/usr/bin/env bash
# kb_adapter.sh — knowledge-base backend dispatcher.
# The local Vault_Brain/*.md tree is ALWAYS the canonical store. This adapter
# is a no-op for all current Tier A strategies (files ARE the store).
#
# FAIL-SAFE: this NEVER exits non-zero. It must never block ingest. Called at
# the tail of daily_ingest.sh as `bash kb_adapter.sh || true`.
# Dispatches on $KB_STRATEGY from config.sh (obsidian|vscode).
# bash 3.2 compatible.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh" 2>/dev/null || true

case "${KB_STRATEGY:-obsidian}" in
  obsidian|vscode)
    # Tier A: plain local .md, the files ARE the store. Nothing to sync.
    exit 0
    ;;
  *)
    echo "kb_adapter: unknown KB_STRATEGY='${KB_STRATEGY}' — treating as local markdown (no-op). Valid: obsidian|vscode. See docs/kb-obsidian.md or docs/kb-vscode.md" >&2
    exit 0
    ;;
esac
