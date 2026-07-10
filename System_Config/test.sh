#!/usr/bin/env bash
# test.sh — template self-tests. Run before pushing / in CI.
#
#   bash System_Config/test.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSCFG="$ROOT/System_Config"

FAIL=0

run() {
  local desc="$1"; shift
  echo "→ $desc"
  if "$@"; then
    echo "  [ok] $desc"
  else
    echo "  [FAIL] $desc"
    FAIL=1
  fi
}

# ---------------------------------------------------------------------------
# 1. Syntax check every owned script.
# ---------------------------------------------------------------------------
SCRIPTS="$ROOT/bootstrap.sh"
for f in "$SYSCFG"/*.sh; do
  [ -e "$f" ] || continue
  SCRIPTS="$SCRIPTS $f"
done

for f in $SCRIPTS; do
  run "bash -n $(basename "$f")" bash -n "$f"
done

# ---------------------------------------------------------------------------
# 2. shellcheck --severity=error, if available.
# ---------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  for f in $SCRIPTS; do
    run "shellcheck --severity=error $(basename "$f")" shellcheck --severity=error "$f"
  done
else
  echo "[skip] shellcheck not installed (brew install shellcheck)"
fi

# ---------------------------------------------------------------------------
# 3. Rules drift gate.
# ---------------------------------------------------------------------------
run "sync_rules.sh --check" bash "$SYSCFG/sync_rules.sh" --check

# ---------------------------------------------------------------------------
# 4. Vault schema gate.
# ---------------------------------------------------------------------------
run "migrate_vault.sh" bash "$SYSCFG/migrate_vault.sh"

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: all checks passed"
else
  echo "FAIL: one or more checks failed"
fi
exit "$FAIL"
