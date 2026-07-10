#!/usr/bin/env bash
# vault_snapshot.sh — daily git snapshot of Vault_Brain/.
# Stages ONLY Vault_Brain, commits if there's something new, pushes if a
# remote is configured. Never touches anything outside Vault_Brain (the
# single `git add Vault_Brain` guarantees this) and never hijacks an
# in-progress staged commit.
#
# Scheduled via launchd — see vaultsnapshot.plist.tmpl (label com.<username>.vaultbrain.vaultsnapshot)
#   Activate:    bash System_Config/install_vault_snapshot.sh
#   Manual run:  bash System_Config/vault_snapshot.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

LOG="$LOG_DIR/vault_snapshot.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG"
ts() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "vault_snapshot start"

cd "$WORKSPACE"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "not a git repo — skipping"
  exit 0
fi

if ! git diff --cached --quiet; then
  log "index has staged changes — skipping so we don't hijack them"
  exit 0
fi

git add Vault_Brain

if git diff --cached --quiet; then
  log "no vault changes"
  exit 0
fi

git commit -m "chore(vault): snapshot $(date +%F)" >> "$LOG" 2>&1

if git remote get-url origin >/dev/null 2>&1; then
  # healthcheck.sh also publishes docs/status.* to origin/main from its own
  # worktree every 4h — push_main's rebase-before-push avoids racing it.
  push_main >> "$LOG" 2>&1 || log "push failed after retries — snapshot committed locally"
else
  log "no origin remote — snapshot committed locally"
fi

log "vault_snapshot done"
