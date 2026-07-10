# Improvements Backlog

Twenty independent cards: 1–10 close today's gaps, 11–20 future-proof the
template against change (model churn, spec drift, roster growth, tool lock-in).
Each card is **what · why · a fix prompt** you can paste into any capable model —
prompts are self-contained; run them from the workspace root. Items 1–4 unblocked
the public release and are done, as is 5; the rest can land in any order.
Status lines are appended to cards as they land — keep this file current.

## Today's gaps (1–10)

### 1. Cross-platform automation shim — ✅ DONE 2026-07-09
**Landed:** `SCHEDULER` detect + `install_cron_job`/`remove_cron_job` in `config.sh`; all 5 installers branch to cron on Linux, print manual guidance elsewhere; macOS path unchanged. Windows native scheduling still open (WSL works via cron).
**Why:** the whole `System_Config/` layer is macOS `launchd` — the single biggest blocker to "anyone can install."
> **Prompt:** "In `System_Config/`, the 5 `install_*.sh` scripts render `.plist.tmpl` files for macOS launchd. Add an OS branch: on Linux render an equivalent `cron` entry, on Windows print WSL/Task-Scheduler guidance. Keep macOS behavior byte-identical. Add a `SCHEDULER` detect in `config.sh`. Show me the diff for one installer (`install_daily_ingest.sh`) as the pattern before doing the rest."

### 2. Single-source orchestrator rules — ✅ DONE 2026-07-09
**Landed:** shared sections live in `System_Config/orchestrator-rules.md`; `sync_rules.sh` regenerates the `SHARED:*` marker regions in `CLAUDE.md` + `.agents/AGENTS.md`; `--check` exits 1 on drift (verified with a live drift test).
**Why:** `CLAUDE.md` and `.agents/AGENTS.md` are near-verbatim mirrors — every rule change must be edited twice and drifts (see docs/FAILURE_MODES.md F6).
> **Prompt:** "`CLAUDE.md` (Claude) and `.agents/AGENTS.md` (Gemini) duplicate the same orchestration rules. Extract the shared body into `System_Config/orchestrator-rules.md` and have both files include/reference it, or add a `make sync-rules` that regenerates both from the source. Do not change the actual rules. Prove the two outputs match."

### 3. Install doctor + clean uninstaller — ✅ DONE 2026-07-09
**Landed:** `./bootstrap.sh --check` (tools + job status + FDA reminder), `--uninstall` (confirm, bootout + plist/cron removal, data untouched), `--help`.
**Why:** there's no way to verify a healthy install or cleanly remove the launchd jobs.
> **Prompt:** "Add `./bootstrap.sh --check` (prints found/missing for `claude|gemini|gh|node|npx|python3`, launchd job status via `launchctl print`, FDA reminder) and `./bootstrap.sh --uninstall` (boots out all 5 launchd jobs and removes the plists, leaves data untouched). Reuse the existing bootout/bootstrap fallback pattern already in `System_Config/install_*.sh`. Non-destructive; confirm before removing."

### 4. Vault auto-commit snapshots — ✅ DONE 2026-07-09
**Landed:** `vault_snapshot.sh` + installer + plist (daily INGEST_HOUR+1:15). Vault-only commits, skips when the index is staged, push failure non-fatal. First snapshot committed same day.
**Why:** `Vault_Brain/` is auto-fed by ingest but never committed — a crash loses knowledge.
> **Prompt:** "Add `System_Config/vault_snapshot.sh` that runs `git add Vault_Brain && git commit -m 'chore(vault): snapshot' && git push` (skip if no changes), plus an installer `install_vault_snapshot.sh` scheduling it daily after ingest. Model it on the existing `install_daily_ingest.sh`. Guard against committing secrets or `.mcp.json`."

### 5. Secrets hygiene — ✅ DONE 2026-07-09
**Landed:** `.gitignore` covers `.mcp.json`/`*.key`/`.env*` (with `!.env.example`) / logs; `.env.example` documents the `~/.config/anthropic/key` path; audit found zero tracked secrets and a credential-free `.mcp.json`.
**Why:** `.mcp.json` and API keys risk being committed as the template gets shared publicly.
> **Prompt:** "Audit `.gitignore` and confirm `.mcp.json`, `*.key`, `.env`, `System_Config/logs/` are ignored. Add a `.env.example`, document the `~/.config/anthropic/key` path `daily_ingest.sh` reads, and add a bootstrap warning if `.mcp.json` contains a non-empty token. Show what's currently tracked that shouldn't be: `git ls-files | grep -Ei 'key|env|secret|token'`."

### 6. MCP server presets + picker — ✅ DONE 2026-07-09
**Landed:** `.mcp.json.example` ships filesystem/github/fetch presets under `_disabled_examples` (copy into `mcpServers` to enable, then allow-list in `.claude/settings.json`); bootstrap points at them on seed. No interactive picker — the presets + message cover it.
**Why:** `.mcp.json.example` is empty; users re-add the same servers per project.
> **Prompt:** "Populate `.mcp.json.example` with 3–5 common MCP servers (filesystem, github, etc.) disabled by default, and add a bootstrap prompt to enable a subset, writing to `.mcp.json`. Never overwrite an existing `.mcp.json`. Document in `README.md`."

### 7. Template self-tests (CI) — ✅ DONE 2026-07-09
**Landed:** `System_Config/test.sh` (bash -n + shellcheck errors + rules-drift + schema checks, PASS/FAIL summary) + `.github/workflows/ci.yml` running it on every push/PR. One shellcheck ERROR fixed (run_agent.sh shell directive); 54 style warnings inventoried, deliberately unfixed.
**Why:** nothing validates the scripts before a user clones.
> **Prompt:** "Add `shellcheck` over every `*.sh` in the repo root and `System_Config/`, plus `bash -n` syntax checks, wired as a `.github/workflows/ci.yml` GitHub Action and a local `System_Config/test.sh`. Fix any shellcheck errors it surfaces in the existing scripts. Start by listing the errors before fixing."

### 8. Upstream update mechanism — ✅ DONE 2026-07-10
**Landed:** `./bootstrap.sh --update` (dry-run) / `--update --apply`. Fetches `TEMPLATE_UPSTREAM` (env-overridable), diffs system paths only (`System_Config/` minus config.sh+logs, both agent dirs, CLAUDE.md/.AGENT.MD, bootstrap.sh, docs/, VERSION/CHANGELOG, .github/), never touches `Projects/`, `Vault_Brain/`, `Final_Products/`, `.mcp.json`. User's `config.sh` is never overwritten — upstream's lands beside as `config.sh.upstream`. Refuses to apply over uncommitted system-path edits; self-updates bootstrap.sh last; leaves changes staged for the user's own commit. Verified by full downstream simulation (old clone + user data + custom config → update → data and settings intact, test.sh passes).
**Why:** an installed user can't pull template improvements without clobbering their `Projects/`/`Vault_Brain/` data.
> **Prompt:** "Design and add `./bootstrap.sh --update`: fetches the template's upstream, updates only system files (`System_Config/`, `.claude/agents/`, `.agents/skills/`, `CLAUDE.md`, `bootstrap.sh`) and never touches `Projects/`, `Final_Products/`, `Vault_Brain/`, `.mcp.json`. Use a git strategy (sparse checkout or path-scoped merge). Dry-run by default; show the file list before applying."

### 9. First-run onboarding — ✅ DONE 2026-07-09
**Landed:** root `WELCOME.md` (first 15 minutes: open, delegate, clip, ingest, check) + disposable sandbox `Projects/example/` (hello.sh + toy BRIEF). `Projects/example-project/` stays as the reference brief; bootstrap prints the WELCOME pointer.
**Why:** a fresh clone drops the user into a cold workspace with no guided start.
> **Prompt:** "Create a `WELCOME.md` shown after `./bootstrap.sh` completes (echo a pointer to it) that walks a new user through: open in Claude/Gemini, try one orchestrator command, add a first web clip, watch it ingest. Seed one tiny example under `Projects/example/` with a `BRIEF.md` demonstrating the eng-manager flow. Keep it deletable."

### 10. Ingest resilience & observability — ✅ DONE 2026-07-09
**Landed:** quota-wall detection (2 consecutive bad clips → loud log + stop, next scheduled run retries); summary line includes pending count; healthcheck Layer I "Ingest" surfaces pending/total in the status page.
**Why:** the ingest hits a provider quota wall (~5–6 clips/run) with no visible metrics; failures are quiet.
> **Prompt:** "In `System_Config/daily_ingest.sh` add exponential backoff + a clear log line on quota/budget exit (not a silent stop), and have `healthcheck.sh` surface per-source counts (clips pending, ingested, last-run status) into the status page it already writes. Don't change the one-clip-per-call design. Show the healthcheck diff."

## Future-proofing (11–20)

### 11. Central model registry — ✅ CLOSED (not needed) 2026-07-09
**Audit result:** zero hardcoded model IDs anywhere in the template scripts, plists, or agent files — the CLIs run without `--model` and use their configured defaults. Registry would be dead flexibility; reopen only if a script gains a `--model` flag.
**Why:** model IDs churn; scattered hardcodes make every bump a hunt.
> **Prompt:** "Grep the repo for hardcoded model identifiers (`claude-*`, `gemini-*`, `opus`, `sonnet`, `haiku`). Consolidate them into a single `System_Config/models.sh` (e.g. `MODEL_INGEST`, `MODEL_ORCHESTRATOR`) sourced by the scripts, so a model rename is a one-line change. List every occurrence before consolidating."

### 12. Template versioning + CHANGELOG — ✅ DONE 2026-07-09
**Landed:** `VERSION` (0.1.0), `CHANGELOG.md` (Keep-a-Changelog, Unreleased), bootstrap banner prints the version, convention documented in README.
**Why:** users and the `--update` mechanism (#8) need to know what version they have.
> **Prompt:** "Add a `VERSION` file (semver, start `0.1.0`) and a `CHANGELOG.md` (Keep-a-Changelog format) at the repo root. Have `bootstrap.sh` print the version on run. Document the release/bump convention in `README.md`. Don't invent history — start the changelog at Unreleased."

### 13. Vault schema versioning + migration path — ✅ DONE 2026-07-09
**Landed:** `Vault_Brain/.vault-schema` (v1), `migrate_vault.sh` (up-to-date no-op, empty migration case, newer-than error), convention in `Vault_Brain/README.md`.
**Why:** the wiki schema in `Vault_Brain/CLAUDE.md` will evolve; old vaults must upgrade without hand-editing.
> **Prompt:** "Add a `schema_version` marker to `Vault_Brain/` (e.g. a `.vault-schema` file) and a `System_Config/migrate_vault.sh` stub that reads current vs target version and no-ops when equal. Document the migration convention in `Vault_Brain/README.md`. Ship version 1 matching today's schema; no data changes."

### 14. Config schema validation on load — ✅ DONE 2026-07-09
**Landed:** `validate_config()` in config.sh (13 required vars, dir existence, hour/minute/provider ranges; returns, never exits) wired into all six installers. Verified both pass and fail paths.
**Why:** as `config.sh` grows, a typo silently breaks background jobs.
> **Prompt:** "Add a `validate_config()` function to `System_Config/config.sh` that asserts required vars are set and paths exist, called at the top of each `install_*.sh` and the ingest/process scripts. On failure print the offending var and exit non-zero. Keep it pure bash 3.2. Show one script wired as the pattern."

### 15. Agent-roster scaffolder — ✅ DONE 2026-07-09
**Landed:** `new_agent.sh <name> "<scope>"` renders both harness files from the coder pattern; dry-run default, `--write` to create, refuses overwrites, prints the .AGENT.MD registration reminder.
**Why:** every new agent must be added in TWO places (`.claude/agents/` + `.agents/skills/`) or the providers drift.
> **Prompt:** "Add `System_Config/new_agent.sh <name> <scope>` that scaffolds both `.claude/agents/<name>.md` and `.agents/skills/<name>/SKILL.md` from a shared template and reminds the user to register it in `.AGENT.MD`'s coordination matrix. Model the templates on the existing `coder` entries. Dry-run print before writing."

### 16. Skill index + versioning — ✅ DONE 2026-07-09
**Landed:** `## Skill Index` table in `.AGENT.MD` (all six skills, v1); `sync-skills.sh` warns non-fatally when a repo skill is missing from the index.
**Why:** skills will proliferate; without an index they're undiscoverable and unversioned.
> **Prompt:** "Add a skill index (extend `.AGENT.MD`) listing every skill with name, one-line purpose, location, and a version field. Add a `sync-skills.sh` check that flags skills missing from the index. Don't change skill behavior — just catalog them."

### 17. CLI dependency pinning + upstream-break detector — ✅ DONE 2026-07-09
**Landed:** `deps.sh` records tested versions; `--check`/`--check-deps` prints an informational drift line on mismatch. Never blocks.
**Why:** `gh`, Playwright, `agy`, `npx skills` all evolve; a breaking upstream change fails silently in a background job.
> **Prompt:** "Add a `System_Config/deps.sh` recording the tested version of each external CLI (`gh`, `node`, `playwright-cli`, `agy`/`gemini`, `claude`) and a `--check-deps` mode in `bootstrap.sh` that warns when the installed version differs from tested. Informational, never blocks. List current installed versions first."

### 18. Provider-agnostic invocation layer — ✅ DONE 2026-07-09
**Landed:** `System_Config/run_agent.sh` (sourced library, byte-equal flags + watchdog) now the single provider branch; `daily_ingest.sh` and `friday_process.sh` source it. Flag changes happen in one place.
**Why:** the claude-vs-gemini flag differences are copy-pasted across `daily_ingest.sh` and `friday_process.sh`; a new provider or flag change means editing every script.
> **Prompt:** "Extract the provider-branch `run_claude` function in `System_Config/daily_ingest.sh` and `friday_process.sh` into one shared `System_Config/run_agent.sh` that both source, so provider/flag logic lives in one place. Behavior must stay identical per provider. Diff both callers before and after."

### 19. Workspace export/import (anti-lock-in) — ✅ DONE 2026-07-09
**Landed:** `export_workspace.sh` (dated tar.gz, secrets/logs/git excluded) + `import_workspace.sh` (refuses non-empty targets). Round-trip diff verified empty.
**Why:** the whole value is a portable knowledge system; it should survive a move off this tool/machine as a plain archive.
> **Prompt:** "Add `System_Config/export_workspace.sh` that tars `Vault_Brain/`, `Projects/`, `Final_Products/`, and config (excluding secrets, logs, node_modules, .git) into a dated portable archive, plus a matching `import_workspace.sh`. Document in `README.md`. Verify a round-trip (export → fresh dir → import) preserves the vault."

### 20. Longitudinal observability — ✅ DONE 2026-07-09
**Landed:** `logs/metrics.tsv` (date, pending, ingested-total, jobs, wiki pages) appended each healthcheck run, header once, append-only; last snapshot surfaced in the status page via Layer I.
**Why:** `healthcheck.sh` shows only the current snapshot; trends (ingest volume, failure rate over weeks) are invisible.
> **Prompt:** "Have `healthcheck.sh` append a dated one-line metrics record (clips ingested, jobs healthy/failed, vault page count) to `System_Config/logs/metrics.tsv` on each run, and add a small section to the status page charting the last 30 records. Append-only; don't rewrite history. Show the healthcheck diff."

---

# Round 2 — Wargame 2026-07-10 (automation · ingestion · second-brain)

Adversarial pass over the three core loops, with live log evidence. Cards 21–24
were fixed on the spot; 25–32 carry lesser-model prompts like round 1.

### 21. Ingest concurrency lock — ✅ DONE 2026-07-10
**Was:** `daily_ingest.sh` had no lock (friday_process did); RunAtLoad + calendar + manual runs raced on the manifests and could double-bill clips — the log showed four overlapping-window manual runs on 2026-07-09.
**Landed:** atomic `mkdir` lock with 4h stale-reclaim; second instance exits 0 with a log line; lock ordering guarantees a losing instance can't remove the winner's lock.

### 22. Per-run spend cap + oversize guard — ✅ DONE 2026-07-10
**Was:** only a per-clip budget; a 17-clip backlog could burn 17 × $1 in one unattended run. No size guard — a 5MB clip burns the full watchdog+budget and can trip the quota-wall stop, blocking clips behind it.
**Landed:** `INGEST_MAX_CLIPS_PER_RUN` (default 10 — worst case = 10 × MAX_BUDGET) and `INGEST_MAX_BYTES` (default 500KB, skipped loudly) in config.sh.

### 23. Verification false-negative rebilling — ✅ DONE 2026-07-10
**Was:** the post-ingest check demanded the literal `[[dir/slug]]`; an agent writing `[[dir/slug|alias]]` or `[[dir/slug.md]]` completed the ingest but was marked NO-OP and re-billed run after run.
**Landed:** match the slug substring (still fixed-string, still scoped to `wiki/`). The garbage-content half of this finding is card 29.

### 24. Log rotation — ✅ DONE 2026-07-10
**Was:** every log + `metrics.tsv` appended forever (healthcheck every 4h, ~775 ingest-log lines in days).
**Landed:** `rotate_log <file> [max]` in config.sh; wired into daily_ingest (2000), healthcheck log (2000), metrics.tsv (1000), vault_snapshot.

### 25. Job-failure notifications — ✅ DONE 2026-07-10
**Landed:** healthcheck persists per-check status in `.last_status`; a check newly going FAIL (or ingest recency newly WARN) fires one combined macOS notification via osascript. Transition-based — never repeats, never touches the exit code.
**Why:** WARN/FAIL only changes a webpage nobody opens. The Master Note sat at `_pending Friday summary_` for four straight weeks and nothing said so.
> **Prompt:** "In `System_Config/healthcheck.sh`, after the status page is written, detect state transitions: keep the previous run's PASS/WARN/FAIL counts in `$LOG_DIR/.last_status` and when a check newly becomes FAIL (or ingest recency newly goes stale), fire a macOS notification: `osascript -e 'display notification \"<check> failed\" with title \"Agent Workspace\"'` (guard with `command -v osascript`, never fail the run). One notification per transition, not per run. Show the diff."

### 26. Friday close-out catch-up — ✅ DONE 2026-07-10
**Landed:** `friday_process.sh [YYYY-Www]` week argument (validated); monday_init detects a missing `.fridayclose.snapshot.md` for last week and runs the catch-up, idempotent + non-fatal.
**Why:** the Friday 16:30 job has `RunAtLoad=false`; a Mac asleep/off at that moment skips the week forever. Live evidence: only 2 runs ever fired, both failed, all four Master Note weeks stuck `_pending`.
> **Prompt:** "In `System_Config/monday_init.sh`, before creating the new week's note, check whether LAST week's note (`weekly-logs/<prev-week>.md`) was closed out (friday_process writes a `.fridayclose.snapshot.md` baseline — check its existence). If missing, log 'last week never closed out — running catch-up' and run `bash friday_process.sh` targeted at the previous week (it must accept an optional week argument — add one, defaulting to current). Keep it idempotent. Show diffs for both scripts."

### 27. Single push gateway — ✅ DONE 2026-07-10
**Landed:** `push_main()` in config.sh (rebase+autostash, 3 attempts, 10s apart, returns not exits); vault_snapshot uses it. First production run pushed a snapshot cleanly through it.
**Why:** `vault_snapshot.sh` pushes main from the checkout while `healthcheck.sh` pushes main from a detached worktree every 4h. Already collided once (rejected non-fast-forward on 2026-07-09); a failed snapshot push has no retry until the next day.
> **Prompt:** "Add `push_main()` to `System_Config/config.sh`: `git pull --rebase --autostash origin main && git push origin main`, up to 2 retries with a 10s sleep, returns non-zero on final failure without aborting the caller. Replace the raw `git push` in `vault_snapshot.sh` with it. Leave healthcheck's worktree publish as-is (it already force-syncs to origin/main) but note the ordering in a comment. Show diffs."

### 28. Gemini ingest gating parity — ✅ DONE 2026-07-10
**Landed (evidence-based):** neither agy nor gemini has allow/deny tool flags (gemini's `--allowed-tools` is a deprecated auto-approve list). So: `INGEST_PREFER_SAFE_PROVIDER=1` — `auto` resolution now prefers claude (fine-grained gating) when installed; explicit `INGEST_PROVIDER=gemini` still forces gemini. Vault_Brain/README.md Safety paragraph now states the per-provider gating precisely.
**Why:** the claude branch runs with an explicit tool allowlist and Bash denied; the gemini/agy branch (the DEFAULT when agy is installed) runs `--sandbox --dangerously-skip-permissions` with no tool restrictions — a prompt-injected clip has a wider blast radius than the docs claim.
> **Prompt:** "Check the current agy/gemini CLI docs (`agy --help`, `gemini --help`) for tool-restriction or sandbox-scope flags equivalent to claude's `--allowedTools/--disallowedTools`. If they exist, add them to the gemini branch of `System_Config/run_agent.sh` to match the claude gating. If they don't, change nothing in run_agent.sh; instead (a) make ingest prefer claude when BOTH providers are installed via a new `INGEST_PREFER_SAFE_PROVIDER=1` default in config.sh honored by the provider-resolution block, and (b) document the asymmetry in `Vault_Brain/README.md`'s Safety paragraph. Verify with a DRY_RUN and show which provider resolves."

### 29. Automated vault lint — ✅ DONE 2026-07-10
**Landed:** `vault_lint.sh` (orphans, unindexed sources, stale `updated:`, schema violations; read-only, exit 0) + healthcheck "Vault lint" WARN check. First run surfaced the real drift: 32 unindexed sources, 4 stale pages.
**Why:** the schema documents a weekly lint nothing runs; `wiki/_index.md` lists 8 sources while 25 exist on disk; `updated:` frontmatter dates are stale; garbage-content ingests pass the slug check and are recorded forever.
> **Prompt:** "Create `System_Config/vault_lint.sh` (read-only, exit 0 always): reports (1) wiki pages with no inbound links, (2) sources present on disk but absent from `wiki/_index.md`, (3) wiki pages whose `updated:` frontmatter is >60 days old, (4) wiki pages missing required frontmatter keys (title/type/updated) — the schema is in `Vault_Brain/CLAUDE.md`. Output a short report to `$LOG_DIR/vault_lint.log` and stdout. Wire it as a new healthcheck section (follow healthcheck.sh's begin_section/check pattern, WARN on any finding). No auto-fixing — report only."

### 30. Setup-success probes — ✅ DONE 2026-07-10
**Landed:** healthcheck "Clip freshness" (WARN >14d — clipper misconfig signal) and "Full Disk Access probe" (greps newest launchd .err for Operation-not-permitted). Both PASS on this machine.
**Why:** clipper template import and Full Disk Access are manual, skippable steps whose failure is invisible; clips landing in the wrong folder just look like 'no new clips'.
> **Prompt:** "In `System_Config/healthcheck.sh`, add two checks to the ingest section: (1) 'clip freshness' — mtime of the newest file in the first INGEST_SOURCES dir; WARN if >14 days ('clipper may be misconfigured — check the browser extension vault + path settings'); (2) FDA probe — attempt `ls` of a TCC-protected path the jobs need (the workspace under ~/Documents) from the healthcheck itself and note that a launchd-context EX_CONFIG 78 in `~/Library/Logs/<label>/` means FDA is missing; grep the newest .launchd.err for 'Operation not permitted' and WARN with the FDA steps. Show the diff."

### 31. Fence-aware weekly carry-forward — ✅ DONE 2026-07-10
**Landed:** `infence` toggle in monday_init's awk; fenced blocks (including `---` inside) travel intact with their parent open task. Fixture-tested.
**Why:** `monday_init.sh`'s awk carry-forward tracks indentation but not markdown code fences; a fenced block under an open task (present in the live W28 note) can be swept into or truncate the capture.
> **Prompt:** "In `System_Config/monday_init.sh`, find the awk program that carries open `- [ ]` items forward. Add fence awareness: toggle an `infence` flag on lines matching /^```/ and, while infence==1, treat lines as continuation of the current captured item (never as headers/separators/stop conditions). Add a test: run the carry-forward against a fixture note containing an open task followed by a fenced block and assert the fence travels with the task. Show the awk diff and the test output."

### 32. Manifest hygiene — ✅ DONE 2026-07-10
**Landed:** migration pass drops name-only entries for deleted sources (logged count); hash-bearing lines always kept (they still dedup re-clipped content). Verified with ghost-entry test.
**Why:** entries for deleted sources are kept forever ('source gone — keep name-only'), so manifests grow unbounded across years and mask real state.
> **Prompt:** "In `System_Config/daily_ingest.sh`'s manifest-migration block, extend the per-line pass: a name-only legacy line whose source file no longer exists AND is older than the migration (no hash recoverable) should be dropped, with one summary log line 'pruned N manifest entries for deleted sources'. Hash-bearing lines for deleted files stay (they still dedup re-clipped content). Keep bash 3.2. Show the diff and a before/after line count on a copy of the real manifest."
