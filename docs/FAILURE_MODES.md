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
| F11 | Self-hosted Docker/Podman stack silently crash-loops under a memory-constrained VM | regression guard |
| F12 | A hotfix inside a vendored/upstream git clone gets silently lost | fixed — verify |
| F13 | Embedding binary payloads as base64 through the model's own context is catastrophically expensive for some tokenizers | recurring |
| F14 | A single-tab-bound plugin/MCP bridge silently breaks when a second browser tab opens the same tool | recurring |

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

## F11 — Self-hosted Docker/Podman stack silently crash-loops under a memory-constrained VM

**Symptom:** MCP tool calls that depend on a backend service intermittently
fail with vague errors (e.g. a bare "http error"), while simpler calls to the
same server keep succeeding.
**Root cause:** the container runtime's VM has too little memory for what's
running under load (a JVM backend is a common culprit). The process OOMs and
restarts every ~60-120 seconds; timing-sensitive calls land mid-crash and
fail, while cheap/stateless calls dodge the window and look fine — making it
read like a flaky MCP/API bug instead of a resource ceiling.
**Fix:** before assuming a tool bug, check VM memory and watch for a restart
loop: `podman machine inspect --format '{{.Resources.Memory}}'`, then poll
`podman inspect <container> --format '{{.RestartCount}}'` twice a few seconds
apart — if the count moves, it's crash-looping. Raise the VM's memory
allocation (`podman machine stop && podman machine set --memory <MB> &&
podman machine start`, then bring the stack back up) if it's constrained
relative to what's running inside it.

> **Fix prompt:** "A self-hosted Docker/Podman-backed tool is intermittently
> failing calls that touch its backend with vague/generic errors, while other
> calls to the same tool succeed. Run `podman machine inspect --format
> '{{.Resources.Memory}}'` to check the VM's memory ceiling, then for each
> running container run `podman inspect <name> --format '{{.RestartCount}}'`,
> wait 5 seconds, and run it again — report any container whose count changed
> (that's crash-looping, almost certainly OOM). If found, stop the machine,
> raise its memory (`podman machine set --memory <higher-value>`), restart
> it, and bring the compose stack back up with `podman compose up -d`. Report
> before/after restart counts over a 60+ second window to confirm stability."

## F12 — A hotfix inside a vendored/upstream git clone gets silently lost

**Symptom:** a local config/ops fix living inside a `Projects/<vendored-tool>/`
clone of someone else's repo (or another team's template) mysteriously stops
working after routine git hygiene on that nested repo — a `git pull`,
`checkout .`, or `reset --hard` run for an unrelated reason.
**Root cause:** the fix was made as an uncommitted working-tree edit inside a
foreign git clone. Git has no reason to protect an unstaged, unexplained
diff — any future git operation (by a human or an agent) that resets the tree
wipes it, with no error and no warning.
**Fix:** commit local-only ops tweaks to vendored repos immediately, as their
own commit with a message that says explicitly it's a local deployment fix
and not meant for upstream. Do not push it to the vendor's remote unless it's
an actual intended contribution.

> **Fix prompt:** "For every git repo nested under `Projects/` in this
> workspace, run `git -C <path> status --short`. For any repo showing
> uncommitted changes to config/deployment files (docker-compose.yaml, .env,
> install scripts — not source code), check whether those changes represent a
> working fix for a bug already hit once (check this session's memory/notes
> for context). If so, commit them locally in that repo with a message noting
> they're a local ops fix, not an upstream contribution — do not push unless
> explicitly asked."

## F13 — Embedding binary payloads as base64 through the model's own context is catastrophically expensive for some tokenizers

**Symptom:** a single image/asset upload attempt burns tens or hundreds of
thousands of tokens, or the file gets silently truncated when read back (a
"cap 25000 tokens" style warning) before it can even be embedded.
**Root cause:** some execution contexts tokenize opaque base64 text at close
to 1 token per character — not the usual ~4 characters per token for normal
prose/code. A "just base64 a small file" instinct that's cheap for a 2KB icon
becomes a 300K+ token round trip for a 400KB photo, with no warning until
it's already happened.
**Fix:** check the file's size before ever base64-encoding it for an
execute_code-style call. For anything past roughly 20-30KB, don't inline it
through your own context at all — use whatever the target tool provides for
real uploads (a REST/upload API endpoint, or if the tool is browser-based,
drive its own UI's file input directly via browser automation with the real
file path, which costs zero context tokens regardless of file size). Reserve
inline base64 for genuinely tiny assets like icons and small SVGs.

> **Fix prompt:** "Before embedding any binary file as base64 inside a tool
> call (execute_code, an MCP call, etc.), run `wc -c` on the file. If it's
> under ~20KB, base64 inline is fine. If it's larger, do NOT read/embed the
> base64 — instead check whether the target tool has (a) a native upload API
> taking raw bytes/a URL, or (b) a browser-drivable UI file input you can
> target directly with the real file path via browser automation (`find` for
> the input element, then upload with the real path — no encoding needed).
> Report the file size and which path you're taking before proceeding."

## F14 — A single-tab-bound plugin/MCP bridge silently breaks when a second browser tab opens the same tool

**Symptom:** automated calls to a browser-plugin-based MCP server that were
working start failing with a "no plugin instance connected" (or equivalent)
error, with no change on the calling side.
**Root cause:** some browser-plugin MCP bridges hold exactly one active
WebSocket connection, tied to whichever tab last registered it. Opening a
second tab to the same tool/file (e.g. via browser automation, to do
something the MCP tool set can't do directly like a real file upload)
silently steals or orphans that connection.
**Fix:** before opening a second tab to a tool that already has an active MCP
bridge, check whether the existing tab/session can be reused instead. If a
bridge does break, look in the newly-active tab for an explicit reconnect
affordance (a toolbar toggle, a "connect here" button) rather than assuming
the integration is dead or restarting the whole stack.

> **Fix prompt:** "An MCP tool call is failing with a 'no plugin instance
> connected' (or similar bridge-down) error, and a second browser tab was
> recently opened to the same application. In that tool's UI (the tab you're
> actively driving), look for a toolbar or plugin panel with a
> reconnect/'connect here' affordance and use it to rebind the bridge to the
> active tab. Retry a trivial MCP call afterward to confirm the bridge is
> live again before resuming real work."
