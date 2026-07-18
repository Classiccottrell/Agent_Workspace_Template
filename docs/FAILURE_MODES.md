# Failure Modes & Fix Prompts

Wargame of where this workspace breaks, why, and how to fix it. Each entry ends
with a **fix prompt** you can paste into any capable model — the prompts are
self-contained (file, command, expected output) so the model needs no prior
knowledge of this repo. Run them from the workspace root.

| # | Failure | Severity |
|---|---------|----------|
| F1 | Ingest stops after ~5–6 clips per run | expected behavior |
| F2 | Gemini ingest cost unbounded | fixed — verify |
| F3 | Notes in subfolders never ingested | fixed — verify |
| F4 | launchd jobs never fire | setup gap |
| F5 | Relocated workspace breaks paths | regression guard |
| F6 | Orchestrator rules drift between providers | recurring |
| F7 | Stale README after a script change | recurring |
| F8 | `gh` unauthenticated → git ops fail | setup gap |
| F9 | Fresh Mac missing node/python3/gh | setup gap |
| F10 | Windows install: automation impossible | known ceiling (Linux cron landed) |

---

## F1 — Ingest silently stops after ~5–6 clips per run

**Symptom:** a big clip backlog drains only a few files per day.
**Root cause:** provider quota wall. Each clip is one headless agent call; after
~5–6 calls the provider throttles. `daily_ingest.sh` is designed for this — a
clip is only recorded in the manifest after the wiki link is verified, so
unprocessed clips retry automatically on the next scheduled run. A clip that
fails or no-ops **3 times** is quarantined (skipped, logged as `QUARANTINED`)
via `<source-dir>/.failed.log` so a poisoned clip can't burn budget forever —
fix or remove the clip, then delete its line from `.failed.log` to retry.
**Fix:** none needed; the backlog drains across days. Verify it is actually draining:

> **Fix prompt:** "In the git repo at the current directory, run
> `wc -l Vault_Brain/sources/.ingested.log` and note the count. Then run
> `DRY_RUN=1 bash System_Config/daily_ingest.sh` and report how many clips are
> still pending per source dir. Compare with
> `grep -c 'OK:' System_Config/logs/daily_ingest.log` and the last 3 dated 'daily_ingest done'
> lines of that log. Expected: the manifest line count grows across dated runs
> and pending count shrinks. Clips listed in a source dir's `.failed.log` with
> count 3+ are quarantined — report those filenames; they need manual ingestion
> (then delete their `.failed.log` line)."

## F2 — Gemini ingest runs unbounded / costs spike

**Symptom:** worry that the gemini path has no budget flag.
**Root cause:** gemini's CLI has no `--max-budget-usd` equivalent. Its only
ceiling is the `MAX_SECONDS` wall-clock watchdog, which applies to **both**
provider branches (the `sleep + kill -TERM` wrapper in `run_claude`).
**Fix:** landed — watchdog covers both; comments in the scripts name the ceiling.

> **Fix prompt:** "Open `System_Config/daily_ingest.sh` and
> `System_Config/friday_process.sh`. Confirm each defines a `run_claude`
> function where BOTH the gemini and claude branches are followed by a
> `( sleep \"$MAX_SECONDS\"; kill -TERM ... )` watchdog before `wait`. Confirm
> `MAX_BUDGET` is passed via `--max-budget-usd` on the claude branch only, with
> a comment noting gemini has no cost flag. Report PASS/FAIL per file with line numbers."

## F3 — Notes in subfolders never ingested

**Symptom:** clips filed into `Vault_Brain/sources/<subfolder>/` are invisible.
**Root cause:** the scan is `-maxdepth 1` by design (subfolders may hold
archives). Fixed: each run now logs a WARN naming how many `.md` files sit in
unscanned subfolders, and any subfolder can be added to `INGEST_SOURCES`.
**Fix:** add the subfolder to `INGEST_SOURCES` in `System_Config/config.sh`.

> **Fix prompt:** "Create a test file
> `Vault_Brain/sources/_test_sub/probe.md` with one line of text. Run
> `DRY_RUN=1 bash System_Config/daily_ingest.sh` and check
> `System_Config/logs/daily_ingest.log` for a WARN line counting subfolder
> files. Then run
> `DRY_RUN=1 INGEST_SOURCES='sources:sources/_test_sub' bash System_Config/daily_ingest.sh`
> and confirm probe.md is listed as pending. Delete
> `Vault_Brain/sources/_test_sub/` afterwards. Report both results."

## F4 — launchd jobs never fire

**Symptom:** no log lines ever appear in `System_Config/logs/`; jobs exit 78.
**Root cause:** `/bin/bash` lacks Full Disk Access, so launchd can't open the
workspace under `~/Documents`, or the plists were never installed.
**Fix:** grant FDA per `System_Config/README.md` (drag `/bin/bash` into
System Settings → Privacy & Security → Full Disk Access) and re-run the installers.

> **Fix prompt:** "Run `launchctl list | grep vaultbrain`. For each of the five
> labels (dailyingest, healthcheck, fridayprocess, mondayinit, syncskills) run
> `launchctl print gui/$(id -u)/<label> | grep -E 'state|last exit'`. A last
> exit code of 78 means /bin/bash lacks Full Disk Access — print the FDA steps
> from System_Config/README.md. If a label is missing entirely, run the
> matching `bash System_Config/install_<name>.sh`. Report per-label status."

## F5 — Relocated workspace breaks paths

**Symptom:** after moving/cloning the workspace to a new path, jobs fail.
**Root cause (guarded):** every script derives `$WORKSPACE` from
`config.sh`'s own location — but a future edit could hardcode a path.
**Fix:** keep the invariant; re-run installers after a move (plists embed the old path).

> **Fix prompt:** "Run `grep -rn '/Users/' System_Config/*.sh System_Config/*.tmpl bootstrap.sh`
> and report any hit that is NOT a comment or a `$HOME`-derived default —
> hardcoded absolute user paths are bugs; every path must derive from
> `System_Config/config.sh`'s `WORKSPACE=` line. Then confirm the installed
> plists point at the current checkout:
> `grep WORKSPACE_ROOT ~/Library/LaunchAgents/*vaultbrain* ; pwd`. If they
> point elsewhere, re-run the five `System_Config/install_*.sh` scripts."

## F6 — Orchestrator rules drift between providers

**Symptom:** Claude and Gemini behave differently on the same workspace.
**Root cause:** `CLAUDE.md` (Claude Code) and `.agents/AGENTS.md` (Gemini) are
maintained as mirrors by hand; an edit lands in one and not the other.
**Fix:** diff and reconcile; long-term fix is single-sourcing (see docs/IMPROVEMENTS.md #2).

> **Fix prompt:** "Compare `CLAUDE.md` and `.agents/AGENTS.md` in this repo
> section by section (System Directives, Caveman Protocol, Wiki Queries,
> Orchestration Rules, Git & GitHub, Documentation Integrity, HTML Template).
> List every rule present in one file but missing or different in the other.
> For each mismatch, propose the one-line edit that reconciles them — do not
> change the meaning of any rule, only sync them. Apply after showing me the list."

## F7 — Stale README after a script change

**Symptom:** docs describe behavior the scripts no longer have.
**Root cause:** the Documentation Integrity rule (update the governing doc in
the same task) was skipped.
**Fix:** compare mtimes and close the gap.

> **Fix prompt:** "For each governing doc — `System_Config/README.md`,
> `Vault_Brain/README.md`, root `README.md`, `.AGENT.MD` — list files in its
> scope modified more recently than the doc, using
> `git log -1 --format=%ci -- <path>` for both sides. For each newer file,
> read its git diff since the doc's last commit and state whether the doc is
> now inaccurate; if so, make the minimal in-place doc edit. Never create new doc files."

## F8 — `gh` unauthenticated → git ops fail

**Symptom:** agents try `gh pr create` / pushes and get auth errors.
**Root cause:** `gh` installed but `gh auth login` never completed (or gh absent).
**Fix:** authenticate once; the login persists in the keychain.

> **Fix prompt:** "Run `command -v gh && gh auth status`. If gh is missing,
> print `brew install gh`. If installed but unauthenticated, print
> `gh auth login` and stop (it is interactive — the user must run it). If
> authenticated, verify repo access with `gh repo view --json name` from the
> workspace root and report the result."

## F9 — Fresh Mac missing node / python3 / gh

**Symptom:** skill sync silently `[skip]`s, doc-currency hook never fires,
weekly site generator no-ops.
**Root cause:** optional tools absent; bootstrap now warns but does not block.
**Fix:** install what you need.

> **Fix prompt:** "For each of `node`, `npx`, `python3`, `gh` run
> `command -v <tool>`. For any missing tool print the install command
> (`brew install node`, `brew install python3`, `brew install gh`) and one
> line on what breaks without it: node/npx → skill sync + Playwright;
> python3 → doc-currency hook + site generator; gh → agent git operations.
> Then re-run `./bootstrap.sh` in a terminal and confirm the prerequisite
> block prints [ok] for everything installed."

## F10 — Non-Mac install: Windows automation impossible (known ceiling)

**Symptom:** on Windows, `./bootstrap.sh` runs but no background jobs install.
**Status:** partially closed. `config.sh` now detects the scheduler (`launchd`
on macOS, `cron` on Linux) and the installers write crontab entries via
`install_cron_job` when on Linux. Windows Task Scheduler remains unsupported —
that is the remaining ceiling of "anyone can install".

> **Fix prompt:** "Detect the OS with `uname -s`. On Darwin or Linux, report
> 'automation supported' (launchd / cron respectively — verify with
> `launchctl list | grep vaultbrain` or `crontab -l`). On anything else, print:
> 'Background automation is macOS/Linux-only for now. The agents and
> Vault_Brain still work — run the jobs manually:
> `bash System_Config/daily_ingest.sh` (daily),
> `bash System_Config/monday_init.sh` (Mondays),
> `bash System_Config/friday_process.sh` (Fridays).'
> If asked to implement Windows support, model it on `install_cron_job` in
> `System_Config/config.sh` but emit Task Scheduler XML, keeping macOS and
> Linux behavior unchanged."
