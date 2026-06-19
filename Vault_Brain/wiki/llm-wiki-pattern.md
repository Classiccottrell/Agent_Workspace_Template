---
title: LLM Wiki Pattern
type: concept
tags: [concept, methodology, ai, pkm, process]
updated: 2025-01-01
---

## Summary
The LLM Wiki pattern (popularized as the "Karpathy LLM Wiki") organizes a knowledge base into three layers — immutable Sources, an LLM-maintained Wiki, and a Schema file that the model reads first every session. A language model reads raw sources, distills them into one entity page per concept, and cross-links those pages aggressively, so the wiki improves as material flows in. This vault is a working implementation: [[claude-code]] is the maintainer, [[obsidian]] is the front-end, and the whole approach serves [[knowledge-management]].

## Key Facts
- **Layer 1 — Sources:** raw inputs in `sources/`, never edited after creation, named `YYYY-MM-DD_<slug>`.
- **Layer 2 — Wiki:** one markdown page per entity, with frontmatter (`title`/`type`/`tags`/`updated`) plus Summary, Key Facts, Connections, and Sources sections.
- **Layer 3 — Schema:** the `CLAUDE.md` file defining structure and conventions; the model reads it first on every session.
- Maintenance is create-or-append only — never overwrite or delete; stale claims are struck through with a dated note.
- Cross-linking is the core discipline: every new page scans existing pages for matching terms and adds `[[wikilinks]]`.
- A `_index.md` file is the wiki root and must be updated whenever a page is added or removed.

## Connections
- [[knowledge-management]]
- [[claude-code]]
- [[obsidian]]

## Sources
- [[sources/2025-01-01_example-clip]]
