#!/usr/bin/env bash
# update_active_projects.sh — Sync the ## Active Projects table in Projects/.AGENT.MD
#
# Strategy (merge):
#   • Existing rows are kept if the directory still exists (metadata preserved).
#   • Rows for directories that no longer exist are dropped.
#   • New directories with a BRIEF.md are added with type "Active" / "See BRIEF.md".
#   • Directories without BRIEF.md are never auto-added (avoids noise from dead dirs).
#
# Usage:  bash System_Config/update_active_projects.sh
# Triggers: run after any project create / archive / rename per CLAUDE.md directive.
#           Also surfaced by healthcheck.sh Layer E as a WARN when table is stale.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/config.sh"
else
  WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

python3 - "$WORKSPACE" <<'PYEOF'
import os, re, sys

workspace = sys.argv[1]
projects_dir = os.path.join(workspace, "Projects")
agent_file   = os.path.join(projects_dir, ".AGENT.MD")

if not os.path.isfile(agent_file):
    print(f"ERROR: {agent_file} not found"); sys.exit(1)
if not os.path.isdir(projects_dir):
    print(f"ERROR: {projects_dir} not found"); sys.exit(1)

# ── Read file ─────────────────────────────────────────────────────────────────
with open(agent_file) as f:
    content = f.read()

if not re.search(r'^## Active Projects\s*$', content, re.M):
    print("ERROR: '## Active Projects' heading not found in Projects/.AGENT.MD — nothing updated")
    sys.exit(1)

# ── Parse current table (merge base) ─────────────────────────────────────────
existing = {}   # name -> (type_str, stack_str)
in_section = False
for line in content.splitlines():
    if re.match(r'^## Active Projects\s*$', line):
        in_section = True; continue
    if in_section and re.match(r'^## ', line):
        break
    if in_section and line.startswith('|') and not re.match(r'^\|[-\s|]+$', line):
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 4:
            name = parts[1].strip()
            if name and name.lower() != 'project':
                existing[name] = (
                    parts[2].strip() if len(parts) > 2 else '-',
                    parts[3].strip() if len(parts) > 3 else '-',
                )

# ── Scan Projects/ ────────────────────────────────────────────────────────────
active_dirs = set()
for entry in sorted(os.listdir(projects_dir)):
    path = os.path.join(projects_dir, entry)
    if not os.path.isdir(path): continue
    if entry.startswith('_'): continue
    if entry.startswith('.'): continue
    active_dirs.add(entry)

# ── Merge ─────────────────────────────────────────────────────────────────────
rows = {}  # name -> (type, stack)

# Keep existing entries where the dir still exists
for name, meta in existing.items():
    if name in active_dirs:
        rows[name] = meta

# Add new dirs that have a BRIEF.md
for name in sorted(active_dirs):
    if name in rows:
        continue
    if os.path.isfile(os.path.join(projects_dir, name, "BRIEF.md")):
        rows[name] = ("Active", "See BRIEF.md")

if not rows:
    print("Nothing to write (no qualifying projects found).")
    sys.exit(0)

# ── Build new table ───────────────────────────────────────────────────────────
sorted_names = sorted(rows.keys(), key=str.lower)
table_lines = [
    "| Project              | Type          | Stack Hint          |",
    "|----------------------|---------------|---------------------|",
]
for name in sorted_names:
    t, s = rows[name]
    table_lines.append(f"| {name:<20} | {t:<13} | {s} |")
new_table = "\n".join(table_lines)

# ── Splice into file ──────────────────────────────────────────────────────────
lines = content.splitlines()
out = []
in_section = False

for line in lines:
    if re.match(r'^## Active Projects\s*$', line):
        in_section = True
        out.append(line)
        out.append(new_table)
        out.append("")   # blank line after table
        continue
    if in_section:
        if re.match(r'^## ', line):
            in_section = False
            out.append(line)
        # else: skip old rows, separators, notes, blanks
        continue
    out.append(line)

# Normalise trailing newline
result = "\n".join(out).rstrip("\n") + "\n"

with open(agent_file, "w") as f:
    f.write(result)

added   = [n for n in sorted_names if n not in existing]
dropped = [n for n in existing if n not in rows]
print(f"Active Projects table updated: {len(rows)} project(s) "
      f"({len(added)} added, {len(dropped)} dropped)")
if added:   print(f"  Added:   {', '.join(added)}")
if dropped: print(f"  Dropped: {', '.join(dropped)}")
PYEOF
