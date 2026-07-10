# Welcome — first 15 minutes

You just ran `./bootstrap.sh`. This is the walkthrough. Delete this file when done (see bottom).

---

## 1. Open the workspace

```bash
claude    # or: gemini
```

Run either from the workspace root. Orchestrator rules load automatically —
`CLAUDE.md` for Claude Code, `.agents/AGENTS.md` for Gemini CLI. No setup step.

## 2. Try one command

A vault query (answers from `Vault_Brain/wiki/`, no delegation):

```
wiki/ example
```

A delegation (routes to the eng-manager → coder for `Projects/`):

```
Have the coder add a --greet flag to Projects/example/hello.sh
```

## 3. Feed the brain

Install the Obsidian Web Clipper template (import
`System_Config/obsidian-webclipper-template.json` into the Web Clipper
extension), clip any article, then:

```bash
DRY_RUN=1 bash System_Config/daily_ingest.sh   # preview the queue
bash System_Config/daily_ingest.sh             # ingest for real
```

## 4. Watch it run

```bash
./bootstrap.sh --check
tail -f System_Config/logs/daily_ingest.log
```

Health dashboard:

```bash
bash System_Config/healthcheck.sh
open System_Config/status_page.html
```

---

Delete this file and `Projects/example/` whenever you're done.
