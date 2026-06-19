# Vault_Brain — LLM Wiki Schema
> Karpathy LLM Wiki pattern. Three layers: Sources → Wiki → Schema (this file).

---

## Vault Structure

```
Vault_Brain/
├── CLAUDE.md                  ← schema (this file) — LLM operating instructions
├── .AGENT.MD                  ← agent identity & pipeline rules
├── Weekly_Note_Template.md    ← weekly note scaffold
├── Master_Note_Template.md    ← year-level index template
│
├── sources/                   ← LAYER 1: raw, immutable inputs
│   └── (articles, specs, screenshots, dumps)
│
├── wiki/                      ← LAYER 2: LLM-maintained entity pages
│   ├── _index.md              ← wiki root with all entity links
│   └── <entity-slug>.md       ← one file per concept/person/project/technology
│
├── inbox/                     ← staging: raw captures not yet processed
├── concepts/                  ← atomic extracted notes (processed inbox)
├── weekly-logs/               ← weekly review notes (YYYY-Www.md)
└── archive/                   ← closed weekly logs
```

---

## Layer 1 — Sources (Immutable)

- Files in `sources/` are **never edited** after creation.
- Acceptable types: `.md`, `.json`, `.png`, `.txt`
- Naming: `YYYY-MM-DD_<slug>.<ext>`
- On ingest: create or update the corresponding wiki page for the source's primary entity.

---

## Layer 2 — Wiki (LLM-Maintained)

Each wiki page covers exactly one entity (concept, person, project, technology, organization).

### Page format
```markdown
---
title: <Entity Name>
type: concept | person | project | technology | org
tags: []
updated: YYYY-MM-DD
---

## Summary
<2-4 sentence synthesis. No bullet lists here.>

## Key Facts
- <atomic fact>
- <atomic fact>

## Connections
- [[related-entity]]
- [[related-entity]]

## Sources
- [[sources/YYYY-MM-DD_slug]]
```

### Wiki maintenance rules
- One page per entity — merge duplicates, never split.
- Every claim must trace back to a source or inbox entry.
- Cross-link aggressively: scan existing wiki pages for matching terms → add `[[wikilinks]]`.
- Never delete content — mark stale claims with `~~strikethrough~~` + updated date.
- Contradictions: preserve both claims, note the conflict inline.
- `_index.md` must be updated whenever a page is added or removed.

---

## Layer 3 — Schema (This File)

Defines structure and conventions. The LLM reads this file first on every session.

---

## Operations

### Ingest (new source arrives)
1. Add raw file to `sources/`
2. Extract entities → find or create wiki pages
3. Update `wiki/_index.md`
4. Add summary line to current weekly log

### Automated daily ingestion
- `System_Config/daily_ingest.sh` runs daily via launchd; activate with `System_Config/install_daily_ingest.sh`.
- It finds `.md` clips in `sources/` not already in `sources/.ingested.log` and processes **one clip per `claude -p` call**, so a partial failure only retries that clip.
- Dedup is by **content hash**: `.ingested.log` lines are `<sha256>\t<filename>` (legacy bare-filename lines still honored). A byte-identical clip saved under a different name is skipped, not re-ingested.
- Each call runs with file tools only, **Bash denied**, cwd confined to the vault, `sources/*.md` locked read-only during the run, and per-clip budget + wall-clock caps.
- The agent runs **create-or-append only**: never overwrite a wiki page wholesale, never delete (the vault has no version control). It records a clip in `.ingested.log` only after that clip's call succeeds.
- On macOS, the launchd job needs Full Disk Access granted to `/bin/bash` so it can read the vault under `~/Documents`; headless auth works via the login keychain (an optional `~/.config/anthropic/key` file is a fallback).
- Web clips arrive via the Obsidian Web Clipper template (`System_Config/obsidian-webclipper-template.json`), which writes to `sources/` with `clipped` / `source` / `author` frontmatter.

### Query
1. Search `wiki/` for entity pages: `rg -l "<keyword>" Vault_Brain/wiki/`
2. Read matching pages (max 5 at once)
3. Synthesize answer with `[[citations]]`
4. If answer is novel → file back into wiki as a new page or update

### Lint (weekly, run before archiving)
- Orphan pages: `rg -L "[[" Vault_Brain/wiki/` — pages with no inbound links
- Stale claims: flag pages not updated in 30+ days
- Missing cross-links: scan summaries for entity names not yet wikilinked

---

## Claude Contribution Protocol

### Weekly note — when and how Claude writes

The current weekly note is always `weekly-logs/YYYY-Www.md` (ISO week number, e.g. `2026-W25.md`).

**At the start of a session:** check if the current week's note exists. If not, create it by running `bash System_Config/monday_init.sh` from the workspace root, or create it manually from `Weekly_Note_Template.md`.

**At the end of any session where something was built, decided, or changed:** append one line to `## Claude Sessions`:
```
- YYYY-MM-DD: <what was done — one sentence, past tense>
```

**When a key decision is made:** also add a row to the `## Decisions` table with the decision, rationale, and date.

Do NOT rewrite or summarize other sections. Append only. Weekly logs are the user's space.

### Wiki — when Claude updates pages

Update a wiki page when:
- A new project is started or meaningfully advanced
- A new tool, system, or technology is introduced or configured
- A key design or architecture decision is made
- A source document is ingested into `sources/`

Always update `wiki/_index.md` when adding or removing a wiki page.

---

## Conventions

- ISO dates everywhere: `YYYY-MM-DD`
- Weekly note naming: `YYYY-Www.md` (e.g. `2026-W25.md`) — never human-readable dates
- Slugs: lowercase, hyphens only (`knowledge-management`, not `Knowledge Management`)
- Tags: lowercase, singular (`design`, `ai`, `tooling`, `concept`)
- Weekly logs: append-only — never overwrite existing content
- Inbox: clear every Friday — everything moves to `concepts/` or `wiki/` or is deleted
