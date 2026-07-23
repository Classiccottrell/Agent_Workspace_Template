# brain/council_decisions/ — LLM Council Reports

Written by `skills/llm-council/run_council.sh`, one file per question:
`YYYY-MM-DD-<question-slug>.md`. This directory starts empty; reports
accumulate here as the council runs.

## Report format

Structure lives in `skills/llm-council/templates/decision-report.md`
(frontmatter `title`/`type: council-decision`/`tags`/`updated` +
`## Question`, `## Advisor Positions (Anonymized)` (A–E subsections),
`## Peer Review Notes`, `## Chairman Synthesis`, `## Decision`,
`## Dissents`). Advisor identity stays anonymized (`Advisor A..E`)
throughout the report — the shuffle mapping is per-run and not recorded, by
design, so the chairman's synthesis is judged on content, not on which
advisor said it.

`run_council.sh` writes the report here and appends an index row to
`brain/wiki/index.md` (backup → rewrite → validate → rollback, same safety
discipline as the weekly scripts).
