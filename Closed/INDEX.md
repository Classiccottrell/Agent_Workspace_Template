# Closed — Project Registry

One row per closed project. The archivist appends a row when a project moves from
`Projects/` to `Closed/`. The `closed_pickup.sh` script auto-detects new subfolders
and fills in `unspecified — needs review` as a placeholder outcome.

Column descriptions: **Project** — folder name; **Folder** — markdown link to the
archived folder (spaces percent-encoded); **Outcome** — one of the values below;
**Closed Date** — ISO date the project was archived; **Notes** — context or flags.

Outcome values: `shipped | paused | superseded | abandoned | unspecified — needs review`

| Project | Folder | Outcome | Closed Date | Notes |
|---------|--------|---------|-------------|-------|
