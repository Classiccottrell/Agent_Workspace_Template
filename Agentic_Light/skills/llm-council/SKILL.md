---
name: llm-council
description: Use for high-stakes or ambiguous decisions that benefit from 5 adversarial perspectives plus synthesis — architecture choices, product direction, tradeoffs with no clear right answer. Not for routine implementation questions.
---

# LLM Council

Five advisor personas (`agents/council/{contrarian,first-principles,expansionist,outsider,executor}.md`)
argue a question independently and in parallel. Their positions are
anonymized and cross-critiqued, then a chairman (`agents/council/chairman.md`)
synthesizes a single decision report. This is expensive relative to a normal
agent call — reserve it for decisions worth the cost.

## Workflow

1. **Parallel advisor pass** — for each of the 5 advisors, build a prompt
   from that advisor's role file + the question, invoke it headlessly and in
   parallel (backgrounded, not sequential), capture each to its own file.
2. **Anonymize** — shuffle the 5 outputs into a random `Advisor A..E`
   mapping (re-randomized every run) and strip any identifying model/advisor
   name, producing one bundle.
3. **Peer review** — re-invoke each advisor, in parallel, against the
   anonymized bundle of the *other* four positions, asking it to critique
   and rank them. Collect all 5 critiques.
4. **Chairman synthesis** — invoke the chairman with the anonymized
   positions plus the peer-review notes. The chairman does not introduce a
   6th opinion — it weighs what's already on the table.
5. **Write the report** to `brain/council_decisions/<YYYY-MM-DD>-<topic-slug>.md`
   using `skills/llm-council/templates/decision-report.md` as the structure.
6. **Index it** — append one row to `brain/wiki/index.md` at the
   `<!-- COUNCIL-INDEX-INSERT -->` sentinel, linking `[[<report-filename>]]`.
   Uses the same backup → rewrite → validate → rollback discipline as
   `System_Config/monday_init.sh`'s Master Note edit.

## Invocation

```
bash skills/llm-council/run_council.sh "<question>"
```

Reads the question from `$1`, or from stdin if no argument is given.
Advisor identity, model, and invocation command are configured in
`advisors.json` — provider-agnostic by schema (Claude live today, extensible
to other vendors without changing `run_council.sh`).
