# Karakeep — Tier B capture source (API poller)

Karakeep (self-hosted bookmark app, formerly **Hoarder**, renamed 2025;
v0.32.0, 2026-05-08 — repo `github.com/karakeep-app/karakeep`, docs
`docs.karakeep.app`) stores bookmarks in **SQLite + Meilisearch + binary
assets**. There is **no plain-markdown on disk and no markdown export** → it is
**Tier B**: a *capture source*, not the store. The vault markdown in
`secondbrain/sources/` stays canonical; a poller pulls new bookmarks out of
Karakeep and writes them as contract-shaped `.md` clips.

## Integration: cron/launchd poller

Unlike Obsidian Web Clipper / MarkSnip (which drop a `.md` straight to disk), a
Tier B source needs a bridge. Run a small poller on a schedule:

1. `GET /api/v1/bookmarks` with header `Authorization: Bearer <key>`
   (key from Karakeep **Settings → API Keys**). Cursor pagination:
   `?limit=<n>&cursor=<cursor>`; follow `nextCursor` until exhausted.
2. Track a **high-water mark** on `createdAt` (or persist the last
   `nextCursor`) so each run only fetches new bookmarks.
3. For each new bookmark: convert `content.htmlContent` → Markdown for the body,
   map the fields below, and write one `.md` to `secondbrain/sources/` named
   `YYYY-MM-DD_<safe-title>.md` (the date is `createdAt`).
4. `daily_ingest.sh` then picks the clip up like any other.

## Field map (Karakeep → contract frontmatter)

| Frontmatter | Karakeep source |
|-------------|-----------------|
| `title` | `title` ?? `content.title` |
| `source` | `content.url` |
| `author` | `content.author` |
| `published` | `content.datePublished` |
| `clipped` | `createdAt` |
| `description` | `content.description` ?? `summary` |
| `domain` | `hostname(content.url)` |
| `tags` | `tags[].name` (join with `, `) |
| body | `content.htmlContent` → md (fallback `note` / `summary`) |

## Frontmatter template (ready to adapt)

```yaml
---
title: <title ?? content.title>
source: <content.url>
author: <content.author>
published: <content.datePublished:YYYY-MM-DD>
clipped: <createdAt:YYYY-MM-DD>
description: <content.description ?? summary>
domain: <hostname(content.url)>
tags: source, clipping, <tags[].name...>
---

<content.htmlContent -> markdown   (fallback: note / summary)>
```

## Caveat

Tier B means Karakeep never becomes the source of truth — the poller is
one-way (Karakeep → vault). Edits made to a clip in `secondbrain/sources/` do
**not** sync back. Keep the vault markdown canonical.
