#!/usr/bin/env bash
# sync_rules.sh — regenerate the shared rule sections of CLAUDE.md and
# .agents/AGENTS.md from the single source System_Config/orchestrator-rules.md.
#
#   bash System_Config/sync_rules.sh           # sync both files in place
#   bash System_Config/sync_rules.sh --check   # exit 1 if either file has drifted
#
# The source file defines blocks with `<!-- BLOCK:<name> -->` headers; each
# harness file carries `<!-- SHARED:<name>:BEGIN ... -->`/`<!-- SHARED:<name>:END -->`
# markers whose contents are replaced verbatim. Text outside markers is never
# touched, so provider-specific sections stay authored per-file.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

command -v python3 >/dev/null 2>&1 || { echo "sync_rules: python3 required"; exit 1; }

python3 - "$WORKSPACE" "${1:-sync}" <<'PY'
import re, sys, pathlib

workspace, mode = sys.argv[1], sys.argv[2]
src = pathlib.Path(workspace, "System_Config/orchestrator-rules.md").read_text()

# Parse BLOCK sections out of the source.
blocks = {}
parts = re.split(r'<!-- BLOCK:(\w+) -->\n', src)
for i in range(1, len(parts), 2):
    blocks[parts[i]] = parts[i + 1].rstrip("\n")

drift = False
for rel in ("CLAUDE.md", ".agents/AGENTS.md"):
    t = pathlib.Path(workspace, rel)
    text = t.read_text()
    new = text
    for name, body in blocks.items():
        pat = re.compile(
            rf'(<!-- SHARED:{name}:BEGIN[^>]*-->\n).*?(\n<!-- SHARED:{name}:END -->)',
            re.S)
        if not pat.search(new):
            print(f"sync_rules: {rel} missing SHARED:{name} markers"); sys.exit(1)
        new = pat.sub(lambda m: m.group(1) + body + m.group(2), new)
    if new != text:
        drift = True
        if mode == "--check":
            print(f"DRIFT: {rel}")
        else:
            t.write_text(new)
            print(f"synced: {rel}")
    else:
        print(f"in sync: {rel}")
sys.exit(1 if (drift and mode == "--check") else 0)
PY
