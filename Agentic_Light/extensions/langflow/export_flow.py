#!/usr/bin/env python3
"""Export the Agentic Light agent/council/skill roster as a Langflow-importable
JSON graph. Read-only visualization aid — has zero effect on the rest of
Agentic Light. Regenerate after adding/removing an agent or skill:

    python3 export_flow.py [--out <path>]
"""
import argparse
import glob
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent  # Agentic_Light/
AGENTS_DIR = ROOT / "agents"
COUNCIL_DIR = ROOT / "agents" / "council"
SKILLS_DIR = ROOT / "skills"

# Hand-off routing mirrored from agents/README.md's roster tables. Do not
# invent relationships that aren't documented there.
HAND_OFF = {
    "architect": ["coder"],
    "coder": ["qa", "eng-manager"],
    "eng-manager": [],  # terminal: PR gate
    "qa": ["eng-manager"],
    "curator": [],  # terminal
    "creative-director": [],  # terminal
    "contrarian": ["chairman"],
    "first-principles": ["chairman"],
    "expansionist": ["chairman"],
    "outsider": ["chairman"],
    "executor": ["chairman"],
    "chairman": [],  # terminal
}


def read_frontmatter(path):
    """Lightweight regex-based frontmatter extraction (name/description),
    same style as System_Config/gen_site.py's read_frontmatter — not a full
    YAML parser."""
    with open(path) as f:
        content = f.read()
    if not content.startswith("---"):
        return None
    end = content.find("---", 3)
    if end == -1:
        return None
    fm = content[3:end]
    name_m = re.search(r"^name:\s*(.+)$", fm, re.MULTILINE)
    desc_m = re.search(r"^description:\s*(.+)$", fm, re.MULTILINE)
    if not name_m:
        return None
    desc = desc_m.group(1).strip() if desc_m else ""
    return {"name": name_m.group(1).strip(), "description": desc}


def build_nodes():
    """Returns list of node dicts, laid out in rows by category:
    base roster (row 0), council + chairman (row 1), skills (row 2)."""
    nodes = []

    base_paths = sorted(glob.glob(str(AGENTS_DIR / "*.md")))
    base_paths = [p for p in base_paths if Path(p).name != "README.md"]
    for i, path in enumerate(base_paths):
        info = read_frontmatter(path)
        if not info:
            continue
        nodes.append({
            "id": info["name"],
            "type": "agent",
            "data": {"name": info["name"], "description": info["description"]},
            "position": {"x": i * 220, "y": 0},
        })

    council_paths = sorted(glob.glob(str(COUNCIL_DIR / "*.md")))
    for i, path in enumerate(council_paths):
        info = read_frontmatter(path)
        if not info:
            continue
        nodes.append({
            "id": info["name"],
            "type": "advisor",
            "data": {"name": info["name"], "description": info["description"]},
            "position": {"x": i * 220, "y": 220},
        })

    skill_paths = sorted(glob.glob(str(SKILLS_DIR / "*" / "SKILL.md")))
    for i, path in enumerate(skill_paths):
        info = read_frontmatter(path)
        if not info:
            continue
        nodes.append({
            "id": info["name"],
            "type": "skill",
            "data": {"name": info["name"], "description": info["description"]},
            "position": {"x": i * 220, "y": 440},
        })

    return nodes


def build_edges(nodes):
    node_ids = {n["id"] for n in nodes}
    edges = []
    for src, targets in HAND_OFF.items():
        if src not in node_ids:
            continue
        for tgt in targets:
            if tgt not in node_ids:
                continue
            edges.append({
                "id": f"{src}->{tgt}",
                "source": src,
                "target": tgt,
            })
    return edges


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default=None,
        help="Output path (default: flows/agentic-light-roster.json relative to this script)",
    )
    args = parser.parse_args()

    out_path = Path(args.out) if args.out else Path(__file__).resolve().parent / "flows" / "agentic-light-roster.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    nodes = build_nodes()
    edges = build_edges(nodes)

    flow = {
        "data": {"nodes": nodes, "edges": edges},
        "description": "Agentic Light agent/council/skill roster, auto-exported from agents/*.md, agents/council/*.md, skills/*/SKILL.md frontmatter. Read-only visualization aid.",
        "name": "Agentic Light Roster",
    }

    with open(out_path, "w") as f:
        json.dump(flow, f, indent=2)
        f.write("\n")

    print(f"Agentic Light roster flow exported: {len(nodes)} nodes, {len(edges)} edges -> {out_path}")


if __name__ == "__main__":
    main()
