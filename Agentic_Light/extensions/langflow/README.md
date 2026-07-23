# extensions/langflow/ — Roster Flow Exporter

Optional. Regenerate with `python3 export_flow.py` after adding/removing an
agent or skill. Import the JSON into a local Langflow instance (Settings →
Import Flow, or drag-and-drop onto the canvas) to visualize/edit the agent
graph.

This extension has zero effect on the rest of Agentic Light — it is a
read-only visualization aid, matching root `Agentic_Light/CLAUDE.md`'s
"optional extensions" framing. Nothing else in the scaffold depends on it.

## Usage

```bash
python3 export_flow.py               # writes flows/agentic-light-roster.json
python3 export_flow.py --out <path>  # custom output path
```

Stdlib only — no `pip install` required, no live Langflow SDK dependency.

## What it does

1. Scans `agents/*.md` and `agents/council/*.md` for `name`/`description`
   frontmatter (lightweight regex extraction, same approach as
   `System_Config/gen_site.py`'s `read_frontmatter`).
2. Scans `skills/*/SKILL.md` the same way.
3. Emits one node per agent/advisor/skill, laid out in three rows (base
   roster, council + chairman, skills).
4. Emits hand-off edges mirrored from `agents/README.md`'s roster tables
   (e.g. `architect→coder`, `coder→qa`/`eng-manager`, `qa→eng-manager`, each
   council advisor `→chairman`).
5. Writes `flows/agentic-light-roster.json` in Langflow's rough top-level
   import shape (`{"data": {"nodes", "edges"}, "description", "name"}`).

`flows/agentic-light-roster.json` is checked in as a real generated
snapshot — regenerate it whenever the roster changes.
