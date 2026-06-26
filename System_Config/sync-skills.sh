#!/bin/bash
# sync-skills.sh — sync ~/.agents/skills/ → ~/.claude/skills/ and flag unindexed skills
# WatchPaths trigger: fires when ~/.agents/skills changes (new npx skills add -g install).
# Also runs hourly via StartInterval. macOS /bin/bash 3.2 — no bash 4+ features.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

AGENTS_SKILLS="$HOME/.agents/skills"
CLAUDE_SKILLS="$HOME/.claude/skills"
MASTER_ORCH="$CLAUDE_SKILLS/master-orchestrator/SKILL.md"
SCRIPT_LOG="$LOG_DIR/sync-skills.log"
mkdir -p "$LOG_DIR"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1" | tee -a "$SCRIPT_LOG"; }

log "=== sync-skills START ==="

# ── 1. Sync .agents/skills → .claude/skills ──────────────────────────────────
synced_count=0
if [ -d "$AGENTS_SKILLS" ]; then
  for src_dir in "$AGENTS_SKILLS"/*/; do
    [ -d "$src_dir" ] || continue
    skill_name="$(basename "$src_dir")"
    dst_dir="$CLAUDE_SKILLS/$skill_name"
    if [ ! -d "$dst_dir" ]; then
      cp -r "$src_dir" "$dst_dir"
      log "SYNCED: $skill_name  (.agents/skills → .claude/skills)"
      synced_count=$((synced_count + 1))
    fi
  done
fi
log "Sync complete. new=$synced_count"

# ── 2. Detect unindexed skills + update master-orchestrator ──────────────────
if [ ! -f "$MASTER_ORCH" ]; then
  log "WARN: master-orchestrator SKILL.md not found — skipping index"
  exit 0
fi

python3 - "$CLAUDE_SKILLS" "$MASTER_ORCH" "$SCRIPT_LOG" <<'PYEOF'
import os, re, sys

skills_dir, master, logfile = sys.argv[1], sys.argv[2], sys.argv[3]

def log(msg):
    from datetime import datetime
    line = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line)
    with open(logfile, 'a') as f:
        f.write(line + '\n')

with open(master) as f:
    content = f.read()

listed = set(re.findall(r'~/.claude/skills/([^/\n]+)/SKILL\.md', content))
listed -= {'<skill-name>'}

installed = {
    d for d in os.listdir(skills_dir)
    if os.path.isdir(os.path.join(skills_dir, d)) and d != 'master-orchestrator'
}

unindexed = sorted(installed - listed)

if not unindexed:
    log("INDEX: all skills indexed — nothing to add")
    sys.exit(0)

log(f"INDEX: {len(unindexed)} unindexed skill(s): {', '.join(unindexed)}")
new_entries = '\n'.join(f'~/.claude/skills/{s}/SKILL.md' for s in unindexed)

if '# unrouted' in content:
    content = re.sub(
        r'(# unrouted\n)((?:~/.claude/skills/[^\n]+\n)*)',
        lambda m: m.group(1) + new_entries + '\n',
        content
    )
else:
    content = re.sub(
        r'(\n)(```\n\n## Migration Note)',
        '\n\n# unrouted\n' + new_entries + r'\n\2',
        content
    )

with open(master, 'w') as f:
    f.write(content)

log(f"INDEX: master-orchestrator updated — {len(unindexed)} unrouted skill(s) flagged")
PYEOF

log "=== sync-skills DONE ==="
