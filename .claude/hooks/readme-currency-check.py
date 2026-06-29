#!/usr/bin/env python3
"""
readme-currency-check.py — PostToolUse hook for Agent Workspace Template.

After any Write/Edit/MultiEdit, if the edited file is a tracked source file
(not a README, generated output, or vendor path), injects a directive reminding
the agent to review and amend any governing docs that are now out of date.

Reads the hook payload as JSON on stdin; emits PostToolUse JSON on stdout.
Always exits 0 (never blocks an edit). Self-contained stdlib (py3.6+ safe).
"""
import json
import os
import sys

# Derive workspace root from this file's location:  hooks/ -> .claude/ -> workspace/
WORKSPACE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Basenames that ARE the docs we amend (editing them must not re-trigger the check).
SKIP_BASENAMES = {
    "README.md", "CONTRIBUTING.md", "INSTALL.md",
    "status_page.html", "status.json", "INDEX.md",
    "README.html",
}
# Path fragments that are generated, vendored, history, or hook internals.
SKIP_FRAGMENTS = (
    "/Final_Products/",
    "/.git/",
    "/node_modules/",
    "/dist/",
    "/archive/",
    "/.claude/hooks/",
    "/System_Config/logs/",
    "/System_Config/status_page.html",
    "/System_Config/status.json",
)


def governing_hint(rel: str) -> str:
    """Return a targeted hint based on which part of the workspace changed."""
    if rel.startswith(".claude/agents/") or rel == ".AGENT.MD":
        return ("Update .AGENT.MD (agent roster table) and the Agent Dispatch routing "
                "line in CLAUDE.md if the agent's scope or routing changed.")
    if rel.startswith("System_Config/"):
        return ("Check System_Config/README.md — if a script, plist, or installer "
                "changed, update the table and any relevant command examples there.")
    if rel.startswith("secondbrain/") or rel.startswith("Vault_Brain/"):
        vault_readme = "secondbrain/README.md" if rel.startswith("secondbrain/") else "Vault_Brain/README.md"
        return (f"Check {vault_readme} and the vault CLAUDE.md — if the ingest "
                "pipeline, schema, or clipper contract changed, update them now.")
    if rel.startswith("Projects/"):
        return ("Check the project's BRIEF.md and README.md — update acceptance "
                "criteria or stack notes if you changed scope or structure.")
    if rel.startswith("docs/"):
        return "Check README.md root and .AGENT.MD — update any cross-references that point to this doc."
    return ("Check the nearest README.md and root .AGENT.MD for any section that "
            "references this file. Amend before finishing the turn.")


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    ti = payload.get("tool_input") or {}
    tr = payload.get("tool_response") or {}
    path = ti.get("file_path") or tr.get("filePath") or ""
    if not path:
        return

    apath = os.path.abspath(path)
    if not apath.startswith(WORKSPACE + os.sep):
        return  # edit outside this workspace — no-op

    base = os.path.basename(apath)
    if base in SKIP_BASENAMES or any(frag in apath for frag in SKIP_FRAGMENTS):
        return

    rel = os.path.relpath(apath, WORKSPACE)
    hint = governing_hint(rel)

    msg = (
        "[README currency] You just edited `{rel}`. "
        "Per the doc-currency rule (CLAUDE.md → Documentation Integrity): "
        "before finishing this turn, review the governing docs for staleness "
        "and amend any that are now out of date. {hint} "
        "If nothing is stale, say so briefly."
    ).format(rel=rel, hint=hint)

    out = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": msg,
        },
        "suppressOutput": True,
    }
    sys.stdout.write(json.dumps(out))


if __name__ == "__main__":
    main()
