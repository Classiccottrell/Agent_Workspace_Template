# KB Guide: VS Code + MarkSnip

This is **Option 2** for the Vault_Brain knowledge layer. VS Code with the Foam extension provides a full plain-markdown workspace with graph visualisation, wikilink resolution, and backlink panels — closely mirroring the Obsidian workflow. MarkSnip handles web clipping.

---

## Step 1 — Install VS Code

Download VS Code from https://code.visualstudio.com if you don't already have it.

---

## Step 2 — Open the vault

Open the `Vault_Brain/` folder as the VS Code workspace root:

```
File → Open Folder → select Vault_Brain/
```

> **Important:** Open `Vault_Brain/` directly, not the workspace root. Foam's graph and wikilink resolution are scoped to the open folder.

---

## Step 3 — Install extensions

The bootstrap wrote `.vscode/extensions.json` in the `Vault_Brain/` folder with all five recommended extensions. VS Code will prompt you to install them on first open.

To install manually: open the Extensions panel (`⌘⇧X`) and search for each ID:

| Extension | Marketplace ID | Purpose |
|---|---|---|
| **Foam** | `foam.foam-vscode` | Graph, backlinks, `[[wikilinks]]`, daily notes |
| **GitHub Markdown Preview** | `bierner.github-markdown-preview` | Accurate `.md` rendering |
| **Markdown Inline Editor** | `CodeSmith.markdown-inline-editor-vscode` | Edit inline without switching modes |
| **Foam: Paste Image** | `foam.foam-vscode-paste-image` | Paste clipboard images → auto-saved file |
| **Todo Tree** | `Gruntfuggly.todo-tree` | Surface TODO/FIXME markers across all notes |

---

## Step 4 — Foam workspace configuration

After installing Foam, create `Vault_Brain/.vscode/settings.json` (if not already present):

```json
{
  "foam.openDailyNote.directory": "weekly-logs",
  "foam.openDailyNote.filenameFormat": "YYYY-[W]WW",
  "foam.openDailyNote.titleFormat": "Week of YYYY-MM-DD",
  "foam.files.ignore": [
    "**/.git/**",
    "**/node_modules/**"
  ],
  "markdown.links.openLocation": "currentGroup"
}
```

This makes Foam's daily-note command write to `weekly-logs/` using ISO week naming (`2026-W27.md`), matching the vault convention.

---

## Step 5 — Key Foam features

| Feature | How to use |
|---|---|
| **Graph view** | `Foam: Show Graph` from Command Palette (`⌘⇧P`) |
| **Backlink panel** | Open `FOAM BACKLINKS` in the Explorer sidebar |
| **Create wikilink** | Type `[[` and start typing — Foam autocompletes from existing pages |
| **Daily note** | `Foam: Open Daily Note` — opens/creates today's weekly log |
| **Navigate to page** | `Ctrl+Click` on a `[[wikilink]]` |

---

## Step 6 — Install MarkSnip

MarkSnip clips any web page to a clean `.md` file.

1. **Chrome / Chromium:** search "MarkSnip" in the Chrome Web Store.
2. **Firefox:** search "MarkSnip" in Firefox Add-ons.
3. Pin to toolbar for one-click access.

---

## Step 7 — Configure MarkSnip

1. Open **MarkSnip Options** (right-click extension icon → Options).
2. Under **Markdown Options → Front Matter Template**, paste the contents of `System_Config/clipper-templates/marksnip-frontmatter.md` (if present), or use this standard template:

```
---
title: {{title}}
source: {{baseURI}}
author: {{byline}}
published: {{date:YYYY-MM-DD}}
clipped: {{date:YYYY-MM-DD}}
description: {{excerpt}}
domain: {{domain}}
tags: source, clipping{{keywords}}
---

{{content}}
```

3. Under **Download Settings**, set the default download folder to `Vault_Brain/sources/`.
4. Enable **Auto-download** (optional).

---

## Step 8 — Daily workflow

1. **Web clip:** click MarkSnip → file lands in `Vault_Brain/sources/`.
2. **Quick note:** `⌘N` in VS Code → new `.md` (save to `Vault_Brain/sources/` with frontmatter when ready to ingest).
3. **Run ingest** (or let the 07:00 launchd job handle it):
   ```bash
   bash System_Config/daily_ingest.sh
   ```
4. **Search:** `⌘⇧F` in VS Code, or:
   ```bash
   rg "your search term" Vault_Brain/
   ```

---

## Replacing Obsidian features

| Obsidian feature | VS Code equivalent |
|---|---|
| Graph view | Foam: Show Graph |
| Backlinks panel | Foam: BACKLINKS sidebar |
| `[[wikilinks]]` | Foam autocomplete |
| Daily notes | Foam: Open Daily Note |
| Quick switcher | `⌘P` file search |
| Full-text search | `⌘⇧F` |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Foam graph is empty | Ensure you opened `Vault_Brain/` as the workspace root, not the parent folder |
| Wikilinks not resolving | Check Foam extension is enabled; reload window (`⌘⇧P` → Reload Window) |
| MarkSnip saves to wrong folder | Options → Download Settings — set path to `Vault_Brain/sources/` |
