# Closed — Project Registry

One row per closed project. The archivist appends a row when a project moves from
`Projects/` to `Closed/`. The `closed_pickup.sh` script auto-detects new subfolders
and fills in `unspecified — needs review` as a placeholder outcome.

Outcome values: `shipped | paused | superseded | abandoned | unspecified — needs review`

| Project | Outcome | Closed date | Notes |
|---------|---------|-------------|-------|
