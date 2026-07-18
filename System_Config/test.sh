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
# 5. Python compiles; JSON parses. (Catches broken hooks/generators before users do.)
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  for p in "$ROOT/.claude/hooks/readme-currency-check.py" "$SYSCFG/gen_site.py"; do
    [ -f "$p" ] || continue
    run "py_compile $(basename "$p")" python3 -m py_compile "$p"
  done
  for j in "$ROOT/.claude/settings.json" "$ROOT/.mcp.json.example"; do
    [ -f "$j" ] || continue
    run "json valid $(basename "$j")" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$j"
  done
else
  echo "[skip] python3 not installed — py_compile/JSON checks skipped"
fi

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
