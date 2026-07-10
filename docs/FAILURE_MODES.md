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
| F10 | Non-Mac install: automation impossible | known ceiling |
| F11 | Friday close-out silently never runs | live evidence |
| F12 | Snapshot vs healthcheck push race on origin | live evidence |
| F13 | Job failures invisible (no notification channel) | recurring |
| F14 | Concurrent ingest double-billing | fixed — verify |

---

## F1 — Ingest silently stops after ~5–6 clips per run

**Symptom:** a big clip backlog drains only a few files per day.
**Root cause:** provider quota wall. Each clip is one headless agent call; after
~5–6 calls the provider throttles. `daily_ingest.sh` is designed for this — a
clip is only recorded in the manifest after the wiki link is verified, so
unprocessed clips retry automatically on the next scheduled run.
**Fix:** none needed; the backlog drains across days. Verify it is actually draining:

> **Fix prompt:** "In the git repo at the current directory, run
> `wc -l Vault_Brain/sources/.ingested.log` and note the count. Then run
> `DRY_RUN=1 bash System_Config/daily_ingest.sh` and report how many clips are
> still pending per source dir. Compare with
> `grep -c 'OK:' System_Config/logs/daily_ingest.log` and the last 3 dated 'daily_ingest done'
> lines of that log. Expected: the manifest line count grows across dated runs
> and pending count shrinks. If the same clips appear as 'NO-OP' for 3+ runs,
> report those filenames — they are stuck and need manual ingestion."

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

## F10 — Non-Mac install: automation impossible (known ceiling)

**Symptom:** on Linux/Windows, `./bootstrap.sh` runs but no background jobs install.
**Root cause:** the entire automation layer is macOS `launchd` (five plists).
By design the agents, skills, and Vault_Brain work anywhere the CLI runs —
only `System_Config/` scheduling is Mac-bound.
**Fix (deferred):** per-OS scheduler shim — Linux `cron` entries or Windows
Task Scheduler equivalents of the five plists (docs/IMPROVEMENTS.md #1). Until
then this is the documented ceiling of "anyone can install".

> **Fix prompt:** "Detect the OS with `uname -s`. On Darwin, report 'automation
> supported'. On anything else, print: 'Background automation is macOS-only for
> now. The agents and Vault_Brain still work — run the jobs manually:
> `bash System_Config/daily_ingest.sh` (daily),
> `bash System_Config/monday_init.sh` (Mondays),
> `bash System_Config/friday_process.sh` (Fridays), or wire them into cron,
> e.g. `0 7 * * * cd <workspace> && bash System_Config/daily_ingest.sh`.'
> If asked to implement cron support, model it on the launchd installers but
> write crontab entries instead of plists, keeping macOS behavior unchanged."

## F11 — Friday close-out silently never runs

**Symptom:** every Master Note week row stays `_pending Friday summary_` (live: 4 straight weeks).
**Root cause:** the job fires only Fridays 16:30 with `RunAtLoad=false`; a Mac asleep or off at that moment skips the week permanently, and a Claude call that produces no summary fails with one log line nobody reads.
**Fix:** catch-up check (IMPROVEMENTS.md card 26): monday_init detects a missing close-out snapshot and runs it late.

> **Fix prompt:** "Check `Vault_Brain/Master Note.md` for rows still reading '_pending Friday summary_' and `System_Config/logs/friday_process.log` for the last successful run. For each missed week whose note exists in `Vault_Brain/weekly-logs/`, report it. If `friday_process.sh` accepts a week argument (post card-26), run the catch-up for each missed week, oldest first; otherwise report that card 26 is not yet landed."

## F12 — Snapshot vs healthcheck push race

**Symptom:** `logs/vault_snapshot.log` shows `! [rejected] main -> main (non-fast-forward)`; a vault snapshot sits committed locally, unpublished, until the next day at best.
**Root cause:** two unsynchronized writers to `origin/main` — vault_snapshot pushes from the checkout, healthcheck pushes status files from a detached worktree every 4h, no fetch/rebase/retry on the snapshot side.
**Fix:** shared `push_main()` with rebase + retry (IMPROVEMENTS.md card 27).

> **Fix prompt:** "Run `git log origin/main..main --oneline` in the workspace. If local commits exist, run `git pull --rebase --autostash origin main && git push origin main` and report the result. Then grep `System_Config/logs/vault_snapshot.log` for 'push failed' lines and report how many snapshots failed to publish and when."

## F13 — Job failures invisible

**Symptom:** ingest quota-walls for a week, the Master Note stalls, a job crashloops — and the only trace is a WARN on a status page the user never opens.
**Root cause:** `healthcheck.sh` has no user-facing alert channel; WARN/FAIL only changes HTML.
**Fix:** transition-based macOS notifications (IMPROVEMENTS.md card 25).

> **Fix prompt:** "Read `System_Config/status.json` and list every WARN/FAIL item. For each, state in one line what the user should do (grant FDA / run gh auth login / check clipper config / run the ingest manually). Then send ONE summary line via `osascript -e 'display notification ...'` if any FAIL exists (guard with `command -v osascript`)."

## F14 — Concurrent ingest double-billing (fixed — verify)

**Symptom (pre-fix):** two overlapping daily_ingest runs (RunAtLoad + schedule, or manual + scheduled) both saw the same clips as new and both paid to ingest them; manifest writes interleaved.
**Root cause:** no lock (friday_process had one; daily_ingest did not).
**Fix:** landed 2026-07-10 — atomic `mkdir` lock, 4h stale reclaim, losing instance exits cleanly and cannot remove the winner's lock.

> **Fix prompt:** "Verify the lock: `mkdir System_Config/logs/daily_ingest.lock`, then run `DRY_RUN=1 bash System_Config/daily_ingest.sh` — expect rc=0, NO dry-run output, and a log line 'another daily_ingest is running'. Confirm the lock dir still exists afterwards (the loser must not remove it), then `rmdir` it and run again — expect a normal dry-run and the lock released at exit."
