# Local Hero-Selection Pipeline

A local, two-stage Claude pipeline that turns a folder of 200–400 property
photos into a production-ready Hero Report — run by hand or automatically when a
new property folder lands on this machine.

No cloud orchestration — just Python on your Mac. For plain-language setup
aimed at non-coders, see [`INSTALL.md`](INSTALL.md); this document is the
technical deep-dive.

## Files

| File | Purpose |
|---|---|
| `wcm_cli.py` | The `wcm` command — `run` / `watch` / `doctor` wrappers around the engine |
| `pyproject.toml` | Makes `wcm` installable with `pip install -e .` |
| `hero_select.py` | The engine + raw CLI (Stage 1 triage → Stage 2 hero pick) |
| `watch_folder.py` | Watcher: runs the engine automatically on new subfolders |
| `requirements.txt` | `anthropic`, `Pillow`, `watchdog` |
| `com.westcoastmodern.heroselect.plist` | launchd agent to start the watcher at login |
| `SKILL.md` | The Stage-2 system prompt (the full hero rubric) |

## How it works

**Stage 1 — triage (cheap, every image).** Each image is downscaled to 768px on
the long edge and sent one-per-call to `claude-haiku-4-5` with a tiny scoring
prompt. Calls run in parallel. Each returns `{"score":0-60,"isExterior":bool,
"note":"…"}`. Results land in `triage_scores.csv` (sorted high→low).

**Stage 2 — hero pick (full quality, top-N only).** The top N images (default
12) are downscaled to 1568px and sent in **one** call to `claude-opus-4-5` with
the full `SKILL.md` as the system prompt. The model returns the complete Hero
Report → `hero_report.md`.

Two stages because a shoot is too large for one call (Anthropic caps 100
images/request and ~200k context tokens; ~1,600 tokens/image means ~300 images
won't fit).

> Models are configurable at the top of `hero_select.py` (`TRIAGE_MODEL`,
> `HERO_MODEL`), as are the downscale sizes, default top-N, and worker count.

## Setup

```bash
cd Hero-Image-Agent
python3 -m venv .venv && source .venv/bin/activate   # recommended
pip install -e .                                     # installs the `wcm` command
export ANTHROPIC_API_KEY="sk-ant-..."                # required; engine fails clearly if unset
wcm doctor                                           # verify everything is ready
```

`pip install -e .` installs the `wcm` command. Prefer not to install? The raw
scripts still run directly with `python3 hero_select.py …` after
`pip install -r requirements.txt`.

## Run mode 1 — manual

```bash
wcm run /path/to/PropertyName
wcm run /path/to/PropertyName --top 12 --workers 5
# equivalent without installing: python3 hero_select.py /path/to/PropertyName
```

Prints per-image triage progress and the top-N, then writes `triage_scores.csv`
and `hero_report.md` into the property folder, followed by a summary of the top
picks and where the report landed.

| Flag | Default | Meaning |
|---|---|---|
| `--top` | 12 | How many top images go to Stage 2 |
| `--workers` | 5 | Parallel triage workers |
| `--skill` | `SKILL.md` next to the script | Override the Stage-2 prompt file |
| `--resume` | off | Reload an existing `triage_scores.csv` and re-run Stage 2 only |

## Run mode 2 — automatic watcher

Watch a **parent** directory; when a new property subfolder appears and its
contents stop changing for ~30s (copy finished), the engine runs on it
automatically. Folders that already contain `hero_report.md` are skipped.

```bash
wcm watch /path/to/Parent
wcm watch /path/to/Parent --top 12 --workers 5 --scan-existing
# equivalent without installing: python3 watch_folder.py /path/to/Parent
```

`--scan-existing` also processes pre-existing subfolders that have no report yet.

### Start the watcher at login (launchd)

1. Edit `com.westcoastmodern.heroselect.plist` — set the four `CHANGE_ME`
   values: absolute `python3` path (`which python3`), absolute path to
   `watch_folder.py`, the parent directory to watch, and your `ANTHROPIC_API_KEY`.

   > A login launchd agent does **not** read your `~/.zshrc`, so the key must be
   > in the plist's `EnvironmentVariables` block — a shell `export` won't reach it.

2. Install and start:

   ```bash
   cp com.westcoastmodern.heroselect.plist ~/Library/LaunchAgents/
   launchctl load  ~/Library/LaunchAgents/com.westcoastmodern.heroselect.plist
   launchctl start com.westcoastmodern.heroselect
   ```

   Logs: `/tmp/wcm-hero-watch.out.log` and `/tmp/wcm-hero-watch.err.log`.

3. Stop / uninstall:

   ```bash
   launchctl unload ~/Library/LaunchAgents/com.westcoastmodern.heroselect.plist
   ```

**Cron alternative** (poll instead of a persistent watcher) — one line via
`crontab -e`; the full command is in the comments at the top of the plist file.

## Robustness

- Non-image files are skipped (`.jpg .jpeg .png .webp .gif` only).
- A per-image failure (corrupt file, API error, malformed JSON) is logged and
  scored 0 — the run continues.
- The watcher debounces on folder-size stability, won't process a folder twice
  at once, ignores its own output files, and skips folders with a report.

## Outputs (written into the property folder)

- `triage_scores.csv` — `file, score, isExterior, note` for every image, sorted desc
- `hero_report.md` — the full Stage-2 Hero Report (hero horizontal, vertical alt,
  hero 2, shortlist, suggested tour sequence, cuts, flags for Trent)
- `hero_report.html` — styled WCM-branded HTML version of the report with the full
  triage scores table embedded; open in any browser for the formatted view
