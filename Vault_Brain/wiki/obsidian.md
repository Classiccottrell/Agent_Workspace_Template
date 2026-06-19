---
title: Obsidian
type: technology
tags: [tooling, markdown, notes, pkm]
updated: 2025-01-01
---

## Summary
Obsidian is a local-first note-taking application that stores notes as plain markdown files in a folder it calls a vault. It renders `[[wikilinks]]` as navigable connections and builds a graph of the vault, which makes it a natural front-end for the [[llm-wiki-pattern]]. Here it opens the `Vault_Brain/` folder directly so its links line up with the wiki pages Claude maintains.

## Key Facts
- A vault is just a directory of `.md` files — no proprietary database, so the same files are editable by [[claude-code]] and any text tool.
- `[[wikilinks]]` create bidirectional links; the graph view visualizes how entity pages connect.
- The setting `alwaysUpdateLinks: true` keeps links correct when files are renamed.
- The Web Clipper browser extension saves articles straight into `sources/` with structured frontmatter, feeding the auto-ingest pipeline.
- Obsidian regenerates its `.obsidian/` config folder on first open; that folder is git-ignored and never shipped in the template.

## Connections
- [[claude-code]]
- [[knowledge-management]]
- [[llm-wiki-pattern]]

## Sources
- [[sources/2025-01-01_example-clip]]
