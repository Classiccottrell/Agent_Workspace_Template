# KB Guide: Obsidian + Obsidian Web Clipper

This is **Option 1** for the Vault_Brain knowledge layer. Obsidian provides native `[[wikilinks]]`, a graph view, and backlink panels. The Obsidian Web Clipper saves web pages as `.md` files directly to `Vault_Brain/sources/`.

---

## Step 1 — Install Obsidian

Download Obsidian from https://obsidian.md (free, no account required).

---

## Step 2 — Open the vault

Open the `Vault_Brain/` folder as an Obsidian vault:

1. Launch Obsidian.
2. Click **Open folder as vault**.
3. Select the `Vault_Brain/` folder (not the workspace root).
4. Obsidian creates a `.obsidian/` config folder on first open and rebuilds it automatically.

> You can edit the same `.md` files in any text editor without launching Obsidian — the vault is plain markdown.

---

## Step 3 — Install the Obsidian Web Clipper

The Obsidian Web Clipper is a first-party, MIT-licensed browser extension that writes templated `.md` files to any local folder — the Obsidian app does NOT need to be running.

1. **Chrome / Chromium:** search "Obsidian Web Clipper" in the Chrome Web Store.
2. **Firefox:** search "Obsidian Web Clipper" in Firefox Add-ons.
3. Pin to toolbar for one-click clipping.

---

## Step 4 — Configure the Web Clipper

1. Open the Web Clipper extension settings.
2. Navigate to **Templates** and click **Import**.
3. Select the bundled template file:
   ```
   System_Config/obsidian-webclipper-template.json
   ```
4. Set the **output path** to your `Vault_Brain/sources/` directory.
5. Set the **filename format** to `{{date|date:"YYYY-MM-DD"}}_{{title|safe_name}}`.

The template writes frontmatter fields: `title`, `source`, `author`, `published`, `clipped`, `description`, `domain`, `tags`.

---

## Step 5 — Daily workflow

1. **Web clip:** click the Web Clipper icon → `.md` file lands in `Vault_Brain/sources/`.
2. **Quick note:** create a new note in Obsidian → save to `Vault_Brain/sources/` with standard frontmatter when ready to ingest.
3. **Run ingest** (or let the 07:00 launchd job handle it):
   ```bash
   bash System_Config/daily_ingest.sh
   ```
4. **Wiki query:** open `Vault_Brain/wiki/` in Obsidian — the graph shows connections. Or search from the terminal:
   ```bash
   rg "your search term" Vault_Brain/wiki/
   ```

---

## Key Obsidian features

| Feature | How to use |
|---|---|
| **Graph view** | Left sidebar → Graph View icon |
| **Backlinks** | Right sidebar → Backlinks panel |
| **`[[wikilinks]]`** | Type `[[` and start typing — autocomplete from existing pages |
| **Quick Switcher** | `⌘O` — jump to any note by name |
| **Search** | `⌘⇧F` — full-text search across vault |
| **Daily note** | Core plugin — configure to write to `weekly-logs/` |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Web Clipper saves to wrong folder | Extension settings → set Output Folder to `Vault_Brain/sources/` |
| `.obsidian/` folder missing | Re-open `Vault_Brain/` in Obsidian — it regenerates automatically |
| File not processed by ingest | Check `Vault_Brain/sources/.ingested.log` — already logged? |
