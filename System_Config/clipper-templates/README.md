# clipper-templates — Web Clipper Contract

The clipper layer is decoupled by a directory boundary: **any** clipper that
drops a plain `.md` file into `Vault_Brain/sources/` works. `daily_ingest.sh`
picks it up and wikifies it.

## Contract

Each clip is a plain markdown file written to `Vault_Brain/sources/`:

- **Filename:** `YYYY-MM-DD_<safe-title>.md`
- **YAML frontmatter keys:** `title`, `source` (the URL), `author`, `published`,
  `clipped`, `description`, `domain`, `tags`.
- **Body:** the article as markdown.

## Templates

| File | Clipper | Import |
|------|---------|--------|
| `obsidian-webclipper.json` | Obsidian Web Clipper (first-party, MIT) | Clipper Settings → Template → Import. Point `path` at `Vault_Brain/sources/`. |
| `marksnip-frontmatter.md` | MarkSnip (MarkDownload MV3 fork) | Options → Markdown Options → paste into the front/template field; set download folder to `Vault_Brain/sources/`. |

## Notes

- **Omnivore is discontinued** (shut down 2024-11-15). Do not use it.
- Original **MarkDownload** is unmaintained — use the **MarkSnip** fork instead.
