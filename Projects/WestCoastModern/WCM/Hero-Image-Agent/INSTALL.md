# Installation Instructions
## WCM Hero Image Selector Skill

---

## Overview

There are three ways to use the hero skill:

| Mode | What it is | Best for |
|---|---|---|
| **Manual — claude.ai** | Upload photos directly to claude.ai, paste the SKILL.md, run | Mica doing ad-hoc selections from any device |
| **Manual — Claude Cowork** | Point Claude at a local folder on your Mac; no uploading required | Trent reviewing a fresh shoot directly from his machine |
| **Automated — `wcm` Python CLI** | One command runs the whole pipeline on a folder and writes the report into it | Hands-free runs, no uploads, no browser |

Start with one of the manual modes. Add Automated Mode (Mode 3, below) once the workflow is validated.

---

## MODE 1 — Manual (claude.ai)
### No setup required. Ready in 5 minutes.

**Best for:** Mica running a selection session from any device, or when photos are already in Google Drive or Dropbox.

### Step 1: Get Claude access
- Mica needs a claude.ai account (Pro plan recommended for larger image batches)
- URL: https://claude.ai

### Step 2: Load the skill
Before uploading any photos, paste the full contents of `SKILL.md` into Claude with this prompt:

```
I'm going to run a hero image selection session for West Coast Modern.
Here are your instructions:

[PASTE FULL CONTENTS OF SKILL.md HERE]

Ready to receive photos.
```

### Step 3: (Optional but recommended) Load taste reference
If Trent has completed the `TASTE_REFERENCE_TEMPLATE.md`, paste it next:

```
Here is the taste reference for this skill:

[PASTE FULL CONTENTS OF COMPLETED TASTE_REFERENCE_TEMPLATE.md HERE]
```

### Step 4: Upload photos and run
```
Property: [House Name]
Hook: [One sentence about what makes this property unique]
Target: [MLS | Instagram | Email | Feature Story | All]

[UPLOAD PHOTOS — drag and drop up to 20 at a time]

Run the hero selection.
```

### Step 5: Review and confirm
Claude will output the Hero Report. Mica reviews it, confirms the hero pick, and flags anything for Trent. Trent does final sign-off.

### Tips for Manual Mode (claude.ai)
- Upload 20–30 photos at a time for best results
- If you have 200+ photos, do a first pass to pull the top 40–50 exteriors, then run the skill on those
- Always include the property name — it improves output formatting and file references
- Save the Hero Report as a Google Doc in the property folder

---

## MODE 2 — Manual (Claude Cowork + Local Folder)
### No uploads required. Works directly from your Mac. ~2 minutes to start.

**Best for:** Trent reviewing a fresh shoot from his local machine without uploading hundreds of photos. Cowork can read files from a local folder path, so the photos stay where they are.

### What is Claude Cowork?
Claude Cowork is a desktop application that gives Claude direct access to files on your computer. Instead of uploading photos one by one, you point Claude at a folder and it reads the images directly. This is the fastest manual option for large shoots.

### Step 1: Install and open Claude Cowork
- Download the Cowork desktop app if you haven't already
- Sign in with your Anthropic / claude.ai account (Pro plan required)
- Open a new Cowork session

### Step 2: Organize your photos locally
Before running the skill, make sure your photos are in a single folder on your Mac. The standard location is:

```
/Users/[yourname]/Dropbox/WCM/[PropertyName]/photography/raw/
```

Or wherever James has synced the shoot. Any local folder path works.

### Step 3: Load the skill
Paste the full contents of `SKILL.md` into the Cowork session, the same as Mode 1:

```
I'm going to run a hero image selection session for West Coast Modern.
Here are your instructions:

[PASTE FULL CONTENTS OF SKILL.md HERE]

Ready to begin.
```

### Step 4: Point Claude at the folder
Instead of uploading photos, give Claude the local path:

```
Property: [House Name]
Hook: [One sentence about what makes this property unique]
Target: [MLS | Instagram | Email | Feature Story | All]

Photos are in this folder on my Mac:
/Users/[yourname]/Dropbox/WCM/[PropertyName]/photography/raw/

Please read all images in that folder and run the hero selection.
```

Claude Cowork will read the images directly from that path without you uploading anything.

### Step 5: Review and confirm
Claude outputs the Hero Report in the Cowork session. You can ask follow-up questions, request score breakdowns, or ask Claude to compare two specific candidates. When you're done, copy the report and save it to Google Drive.

### Tips for Cowork Mode
- If the folder has 200+ images, you can ask Claude to do a first pass on exteriors only: *"Start with just the exterior shots and give me the top 10 before we go further"*
- You can ask Claude to display the shortlisted images side by side for comparison
- The session stays active — you can have a back-and-forth with Claude about specific images before confirming the hero
- Paste the completed `TASTE_REFERENCE_TEMPLATE.md` at the start of the session for best results

---

## MODE 3 — Automated (Python CLI)
### Runs entirely from Terminal. No uploads, no browser. ~15 minutes to set up.

**Best for:** Mica or Trent running hero selection hands-free from a local folder — point it at a shoot, walk away, come back to a finished report.

---

### Prerequisites

- [ ] **Python 3.9 or later** — check with `python3 --version`
- [ ] **Anthropic API key** — get one at [console.anthropic.com](https://console.anthropic.com) (Trent's account)
- [ ] **This repository cloned locally** — `git clone https://github.com/Classiccottrell/WCM.git`

---

### Step 1: Open Terminal and navigate to the agent folder

```bash
cd /path/to/WCM/Hero-Image-Agent
```

---

### Step 2: Create a virtual environment and install

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

This installs the `wcm` command and all dependencies (`anthropic`, `Pillow`, `watchdog`).

**Verify it worked:**

```bash
wcm --help
```

You should see the two subcommands: `run` and `watch`.

---

### Step 3: Set your API key

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

> **Note:** This only lasts for the current Terminal session. To make it permanent, add the line above to your `~/.zshrc` (Mac default) or `~/.bashrc`, then run `source ~/.zshrc`.

---

### Step 4: Run on a property folder

```bash
wcm run /path/to/PropertyName
```

Replace `/path/to/PropertyName` with the actual folder containing the shoot photos (JPG, PNG, WEBP supported).

**What happens:**
1. Stage 1 — every image is scored 0–60 in parallel using a fast model. Takes ~30–90 seconds for a typical shoot.
2. Stage 2 — the top 12 scoring images are sent to a strong model with the full hero rubric. Takes ~60–120 seconds.

**Outputs written into the property folder:**
- `triage_scores.csv` — every image with its score, Interior/Exterior flag, and a short note
- `hero_report.md` — the full Hero Report (hero pick, vertical alt, shortlist, tour sequence, cuts, flags)

---

### Common options

```bash
# Review more candidates in Stage 2 and use more parallel workers
wcm run /path/to/PropertyName --top 20 --workers 10

# Stage 1 already ran but Stage 2 failed — pick up where you left off
wcm run /path/to/PropertyName --resume

# Use a custom skill file instead of the default SKILL.md
wcm run /path/to/PropertyName --skill /path/to/custom-SKILL.md
```

---

### Reactivating in a new Terminal session

The virtual environment and API key don't persist across Terminal sessions. Each time you open a new window:

```bash
cd /path/to/WCM/Hero-Image-Agent
source .venv/bin/activate
export ANTHROPIC_API_KEY="sk-ant-..."
wcm run /path/to/PropertyName
```

> **Tip:** Add both the `source` and `export` lines to `~/.zshrc` so they load automatically on every Terminal session. You will still need to `cd` to the right folder.

---

### Watch mode (automatic — advanced)

`wcm watch` monitors a parent directory. Drop a new property folder inside and the pipeline starts automatically once the copy finishes (~30 second stability window).

```bash
wcm watch /path/to/Parent
```

```bash
# Also process any existing folders that don't yet have a report
wcm watch /path/to/Parent --scan-existing
```

See the main README for launchd auto-start instructions (runs the watcher at login without opening Terminal).

---

### Troubleshooting

| Symptom | Fix |
|---|---|
| `command not found: wcm` | Run `source .venv/bin/activate` first |
| `ERROR: ANTHROPIC_API_KEY is not set` | Run `export ANTHROPIC_API_KEY="sk-ant-..."` |
| `No images found` | Check the folder path; images must be directly inside it (not in subfolders) |
| Stage 2 timeout / error | Re-run with `--resume` to skip Stage 1 and retry Stage 2 only |
| Scores feel wrong | Add more examples to `TASTE_REFERENCE_TEMPLATE.md` and re-run |

---

## Folder Structure

The standard layout for each property. Photos go in `/raw/`; point `wcm run` at
the property folder (or `wcm watch` at the parent of many).

```
/WCM/
  /[PropertyName]/
    /photography/
      /raw/           ← Photographer uploads here (point wcm at this folder)
      /curated/       ← Hero report can be moved here after review
      /final/         ← Mica/Trent place approved selects here
      /sets/
        /mls/
        /email/
        /instagram/
        /website/
```

---

## Who Does What

| Person | Role in this workflow |
|---|---|
| **Trent** | Completes TASTE_REFERENCE_TEMPLATE.md; runs Cowork sessions; final hero sign-off |
| **Mica** | Runs the skill (manual or automated); reviews reports; confirms selects before Trent |
| **James (Photographer)** | Uploads to Dropbox `/raw/` folder by deadline |
| **Philippe** | Receives confirmed hero list for copy pairing |
| **Jacob** | Receives confirmed hero list for B-roll pairing |

---

## Files in This Repo

```
/
├── SKILL.md                      ← Core skill instructions (v2.0)
├── AGENT.md                      ← Agent identity and capabilities
├── TASTE_REFERENCE_TEMPLATE.md   ← Trent fills this out (10 good + 10 not-hero)
├── WCM_STYLE_PROFILE.md          ← Brand aesthetic extraction
├── INSTALL.md                    ← This file
├── wcm_cli.py                    ← The `wcm` command (run / watch / doctor)
├── pyproject.toml                ← Makes `wcm` installable via pip
├── hero_select.py                ← Two-stage pipeline engine
├── watch_folder.py               ← Folder watcher
├── PIPELINE_README.md            ← Technical deep-dive on the pipeline
└── README.md                     ← Git repo overview
```

---

---

## MODE 3B — Local CLI Pipeline (`.env` file variant)
### Same as Mode 3, but stores the API key in a project `.env` file instead of exporting it each session.

This variant is useful when you don't want to add the API key to `~/.zshrc` permanently, or when running from an IDE/script that sources `.env` automatically.

---

### One-time setup

**Step 1 — Get an Anthropic API key**

1. Go to [console.anthropic.com](https://console.anthropic.com) → API Keys → Create key
2. Copy the key — you'll need it in Step 3

**Step 2 — Create the virtual environment**

From inside the `WCM/Hero-Image-Agent/` directory:

```bash
python3 -m venv .venv
.venv/bin/pip install -e .
```

**Step 3 — Create the `.env` file**

Inside `WCM/Hero-Image-Agent/`, create a file called `.env`:

```
ANTHROPIC_API_KEY=sk-ant-api03-...your-key-here...
```

This file is already in `.gitignore` — the key will never be committed.

---

### Running the pipeline

From `WCM/Hero-Image-Agent/`:

```bash
set -a && source .env && set +a && \
.venv/bin/python3 hero_select.py "/path/to/PropertyName/photos/raw"
```

Or using the `wcm` command after sourcing the env:

```bash
set -a && source .env && set +a && wcm run "/path/to/PropertyName/photos/raw"
```

Replace the path with the actual folder containing the shoot photos (quotes required if it has spaces).

---

### Outputs written into the property folder

| File | What it contains |
|---|---|
| `triage_scores.csv` | Stage 1 score for every image |
| `hero_report.md` | Full Stage 2 hero report with FLAGS FOR TRENT |
| `hero_report.html` | Styled HTML version of the report — open in any browser |

Open `hero_report.html` in Safari or Chrome for the formatted WCM-branded view.

---

### Optional flags

```bash
# Increase candidates passed to Stage 2 (default: 12)
... hero_select.py "/path/to/raw" --top 15

# Increase parallel workers for faster Stage 1 (default: 5)
... hero_select.py "/path/to/raw" --workers 8

# Resume from an existing triage_scores.csv (Stage 1 already done)
... hero_select.py "/path/to/raw" --resume
```

---

### Troubleshooting

| Error | Fix |
|---|---|
| `no such file or directory: .venv/bin/activate` | Run Step 2 of one-time setup |
| `ANTHROPIC_API_KEY is not set` | Run Step 3 of one-time setup |
| `AuthenticationError` / 401 | Key is invalid or revoked — generate a new one at console.anthropic.com |
| Score 0/60 on all images | API key issue — same as above |

---

## Support

If Claude's selections feel off, the fastest fix is more taste reference examples from Trent.
Each new example in `TASTE_REFERENCE_TEMPLATE.md` meaningfully improves output quality.