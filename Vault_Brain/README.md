# Vault_Brain — How to Use This

This is your Obsidian knowledge vault. Open **this folder** (`Vault_Brain/`) in Obsidian — not the parent workspace folder.

> Obsidian regenerates a `.obsidian/` config folder the first time you open this vault. It is intentionally not shipped with the template and should stay git-ignored.

> **No MCP server required.** The vault, the Web Clipper, and the daily auto-ingest pipeline run entirely on Claude Code's built-in file tools — they have no dependency on any MCP server. The Obsidian Web Clipper is a browser extension, not an MCP integration. `.mcp.json` is optional: wire in your own server (e.g. a design/Figma MCP) only if a specific project needs one, then enable it in `.claude/settings.json`.

---

## Weekly Notes — Your Weekly Rhythm

### Monday: start the week
Run from your terminal (from the workspace root):
```
bash System_Config/monday_init.sh
```
This creates `weekly-logs/<ISO-week>.md` from the template — **Sprint** and **Quarter** are filled in automatically, open action items carry forward from last week, and a row is added to the **Master Note** index. Dates are anchored to that week's Monday no matter which day you run it.

### During the week: write in two sections
- **The Signal** — what actually mattered. Decisions, breakthroughs, outputs worth remembering.
- **The Noise** — tasks, links, raw captures. Everything else. Clear this by Friday.

Claude automatically appends to **Claude Sessions** at the end of any AI work session, so you have a log of what was built without doing anything.

### Friday: close the week — automatic
A `friday_process` agent can run on a schedule (launchd). It writes a 1–2 sentence summary of the week into the Master Note index row, builds cross-references from your Signal/Noise projects to the wiki, and stamps a close-out line. The note **stays in `weekly-logs/`** (not archived). Activate once:
```
bash System_Config/install_friday_process.sh
```
Run it on demand anytime: `bash System_Config/friday_process.sh` (idempotent — safe to re-run; it skips if the week is already closed out).

---

## The Wiki — Reference Knowledge

`wiki/` holds one file per topic: projects, tools, concepts, organizations. These are maintained by Claude as work happens — you don't need to write them.

To look something up:
```
rg -l "keyword" wiki/
```

To force an update: tell Claude "update the wiki for X" and it'll find or create the page.

---

## Folder Map

```
Vault_Brain/
├── Master_Note_Template.md   ← weekly index (backlinks + Friday summaries) + key info/links
├── Weekly_Note_Template.md   ← template used by monday_init.sh (Signal/Noise + snippets)
├── CLAUDE.md                 ← AI operating instructions (Karpathy wiki schema)
│
├── weekly-logs/              ← all weekly notes (YYYY-Www.md) — kept here, not archived
├── archive/                  ← older one-off archived notes
│
├── wiki/                     ← one page per entity — LLM-maintained
│   └── _index.md             ← wiki table of contents
│
├── sources/                  ← raw inputs: specs, articles, dumps (immutable)
├── concepts/                 ← atomic extracted notes (processed from inbox)
└── inbox/                    ← staging: raw captures, clear by Friday
```

---

## What Goes Where

| You have... | Put it in... |
|-------------|-------------|
| Something important that happened | The Signal (weekly note) |
| A task, link, or quick capture | The Noise (weekly note) |
| A raw document or spec to reference | `sources/` |
| A half-formed idea to develop | `inbox/` → process to `concepts/` by Friday |
| A web clip (Obsidian Web Clipper) | `sources/` — handled automatically (see below) |

---

## Web Clipper → Auto-Ingest Pipeline

Clips you save from the browser flow into the wiki automatically:

```
Browser (Web Clipper)  →  Vault_Brain/sources/YYYY-MM-DD_Title.md
                              ↓  (daily, automatic)
                          daily_ingest.sh runs Claude headlessly
                              ↓
            new/updated wiki page  +  _index.md  +  a line in this week's Claude Sessions
```

**One-time setup:**

1. **Import the clipper template** — In the Obsidian Web Clipper extension: Settings → Templates → drag in `System_Config/obsidian-webclipper-template.json`. Set the extension's **Vault** to `Vault_Brain`. Clips now land in `sources/` with proper frontmatter.

2. **Activate daily ingestion** — run the installer (creates the log dir, installs and bootstraps the launchd agent):
   ```
   bash System_Config/install_daily_ingest.sh
   ```
   launchd, not cron: if the Mac is asleep at the scheduled time it runs the job at next wake; if it was powered off, it runs at login (`RunAtLoad`).

3. **Grant Full Disk Access to `/bin/bash`** (macOS requirement — this is the *only* binary that needs it). Without it the scheduled job can't read `~/Documents`.
   - The Full Disk Access **+** file picker resists system binaries, so use **drag-and-drop**: open System Settings → Privacy & Security → Full Disk Access; in Finder press ⌘⇧G → `/bin` → drag the `bash` file onto the list; toggle it on.
   - The child `claude` process is covered as launchd's responsible process, so granting `/bin/bash` alone covers the whole job.

4. **Auth — usually nothing to do.** Headless `claude` authenticates via your login keychain, which is unlocked while you're logged into the Mac (when the agent runs). *Optional* fallback for fully-detached runs:
   ```
   mkdir -p ~/.config/anthropic
   printf '%s' 'sk-ant-...' > ~/.config/anthropic/key && chmod 600 ~/.config/anthropic/key
   ```
   `daily_ingest.sh` uses this automatically if present.

**Useful commands:**
- Preview what would be ingested, no Claude call: `DRY_RUN=1 bash System_Config/daily_ingest.sh`
- Run ingestion now: `bash System_Config/daily_ingest.sh`
- Watch the log: `tail -f System_Config/logs/daily_ingest.log`
- Stop auto-ingest: `launchctl bootout gui/$(id -u)/$(whoami | sed 's/.*/com.&.vaultbrain.dailyingest/')`

**Safety** — the ingest agent runs with shell access **denied** (`--disallowedTools Bash`), its working directory confined to the vault, clip files locked read-only during the run, and per-clip budget + time caps. It only **creates or appends** — never overwrites or deletes. Each clip is a separate Claude call, so a failure retries just that clip.

**Dedup** — processed clips are tracked in `sources/.ingested.log` by **content hash** (`<sha256>\t<filename>`), so the same article saved under a different filename won't be ingested twice. Re-running is also idempotent: the agent checks whether the wiki page already links the source and stops if so.

---

## System Health — Status Page

A scheduled health check probes the whole workspace (agents, automation, vault, docs) and writes a dashboard:

```
open System_Config/status_page.html
```

It runs on a schedule (launchd) and the page auto-reloads; run it on demand with `bash System_Config/healthcheck.sh`. Green = healthy; amber/red lists exactly what needs attention. Details in `System_Config/README.md`.

---

## Vault Settings

Set `alwaysUpdateLinks: true` in Obsidian's settings — it keeps wikilinks correct when files are renamed. The `.obsidian/` folder is regenerated by Obsidian on first open and is git-ignored; do not commit it.
