# brain/council_decisions/ — LLM Council Reports

Written by `skills/llm-council/run_council.sh`, one file per question:
`YYYY-MM-DD-<question-slug>.md`. This directory starts empty; reports
accumulate here as the council runs.

## Report format

```markdown
---
title: <Question, short form>
type: decision
tags: [council]
updated: YYYY-MM-DD
advisors: [contrarian, first-principles, expansionist, outsider, executor]
---

## Question
<the exact question posed to the council>

## Advisor Positions
### Contrarian
<anonymized during peer review, attributed here>
...

## Peer Review
<each advisor's anonymized critique of the other positions>

## Chairman Synthesis
<the chairman's synthesis of all positions + peer review>

## Decision
<the final recommendation>

## Dissents
<any advisor positions the chairman's decision does not fully incorporate>
```

`run_council.sh` writes the report here and appends an index row to
`brain/wiki/index.md` (backup → rewrite → validate → rollback, same safety
discipline as the weekly scripts).
