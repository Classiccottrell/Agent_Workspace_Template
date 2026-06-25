# Agent Workspace Template

A one-person, multi-agent operating environment — works with **[Claude Code](https://docs.claude.com/en/docs/claude-code)** and **[Gemini CLI](https://github.com/google-gemini/gemini-cli)** (Antigravity). A root **orchestrator** decomposes work and delegates to five scoped subagents (architect, coder, eng-manager, archivist, curator); a small Obsidian LLM-wiki ("Vault_Brain") holds your durable knowledge and is fed automatically from browser clips; and a set of macOS `launchd` jobs ("System_Config") keep the whole thing ingesting, summarizing, and self-checking in the background. Clone it, run one script, and you have a relocatable knowledge-and-delivery system that runs itself.

**Live overview:** https://classiccottrell.github.io/Agent_Workspace_Template/

---

## Why this exists

A solo operator drowns in context sprawl: scattered notes, half-remembered decisions, and AI workflows reinvented from scratch every session. This template fixes that with one owner per layer — delivery, automation, knowledge — so nothing falls between the cracks. Background jobs do the dull work (ingest, summarize, health-check) while you sleep, and everything you learn compounds in a local wiki instead of evaporating in chat history. The result is clone-and-run, relocatable to any path, and self-checking, so the system tells you when something needs attention.

---

## Prerequisites

- **macOS** — the automation uses `launchd` (the install step is mac-only; the agents and vault work anywhere the CLI runs).
- **AI CLI** — one of:
  - **Claude Code** — `command -v claude && claude --version`
  - **Gemini CLI** — `command -v gemini && gemini --version` (Antigravity)
- **bash** — the stock macOS `/bin/bash` (3.2) is enough; every script targets it (no bash 4+ features).
- **Obsidian** *(optional)* — only needed if you want to browse/edit `Vault_Brain/` and use the Web Clipper. The vault is plain Markdown and works fine without it.
- **Full Disk Access for `/bin/bash`** *(one-time, only if you install the background automation)* — so the scheduled jobs can read your workspace. Setup is in [`System_Config/README.md`](System_Config/README.md).

---

## Quick start

```bash
git clone <your-fork-or-copy-of-this-template> agent-workspace
cd agent-workspace
./bootstrap.sh
```

`bootstrap.sh` is idempotent and never deletes or overwrites your data. It makes the scripts executable, creates the log directory, seeds `.mcp.json` from the example if you don't have one, prints a prerequisite check, and **asks before** installing any background automation (default is No). You can re-run it any time.

Open this workspace in your AI CLI and you're operating:
- **Claude Code** — `claude` from the workspace root. Orchestrator rules load from `CLAUDE.md`; agent roster in `.claude/agents/`.
- **Gemini CLI** — `gemini` from the workspace root. Orchestrator rules load from `.agents/AGENTS.md`; skill roster in `.agents/skills/`.

---

## The three layers

This template is an Integrated Context Management (ICM) folder pattern layered over the [Karpathy LLM Wiki](https://karpathy.github.io/) idea: a structured workspace where each layer has one owner and one job.

| Layer | Folder | Owner | What it holds |
|-------|--------|-------|---------------|
| **1. Delivery** | `Projects/`, `Final_Products/` | eng-manager / archivist | Active project workspaces and shipped artifacts |
| **2. Automation** | `System_Config/` | you (run installers) | `launchd` jobs + scripts that keep the system running |
| **3. Knowledge** | `Vault_Brain/` | curator | Obsidian LLM-wiki: sources → wiki → schema |

### Agent roster

The same five agents are available for both Claude Code and Gemini — the role definitions are identical, only the harness format differs.

| Agent | Scope | Claude Code entry | Gemini entry | Hands off to |
|-------|-------|-------------------|--------------|--------------|
| **architect** | Schema, API, structure design | `.claude/agents/architect.md` | `.agents/skills/architect/SKILL.md` | coder |
| **coder** | Implementation only | `.claude/agents/coder.md` | `.agents/skills/coder/SKILL.md` | orchestrator |
| **eng-manager** | `Projects/` lifecycle | `.claude/agents/eng-manager.md` | `.agents/skills/eng-manager/SKILL.md` | architect, coder |
| **archivist** | `Final_Products/` artifacts | `.claude/agents/archivist.md` | `.agents/skills/archivist/SKILL.md` | orchestrator |
| **curator** | `Vault_Brain/` knowledge | `.claude/agents/curator.md` | `.agents/skills/curator/SKILL.md` | orchestrator |

**Claude Code** — agents are invoked by name via the Task tool; never paste role text into a prompt.  
**Gemini CLI** — skills are loaded from `.agents/skills/<role>/SKILL.md`; the orchestrator entry point is `.agents/AGENTS.md`.

### Layout

```
your-workspace/
├── README.md                   ← this file (spin-up guide / entry point)
├── bootstrap.sh                ← one-command setup
├── .gitignore
├── .claudeignore               ← context-window guard
├── .AGENT.MD                   ← root orchestrator + workspace map (provider-agnostic)
├── CLAUDE.md                   ← Claude Code orchestrator rules ("Caveman Protocol")
├── .mcp.json.example           ← MCP config template (copy to .mcp.json, fill in)
├── .cursor/rules/skill.md      ← design-engineering skill profile (injected for UI work)
├── .agents/                    ← Gemini CLI orchestration root
│   ├── AGENTS.md               ← Gemini orchestrator directives
│   └── skills/                 ← architect, coder, eng-manager, archivist, curator
├── .claude/
│   ├── settings.json           ← project permissions + MCP allow-list
│   └── agents/                 ← architect, coder, eng-manager, archivist, curator
├── System_Config/              ← automation hub (see System_Config/README.md)
│   ├── config.sh               ← shared, relocatable config (sourced by every script)
│   ├── daily_ingest.sh         ← ingest new clips into the wiki
│   ├── friday_process.sh       ← weekly close-out summary + cross-refs
│   ├── healthcheck.sh          ← probe all layers → status_page.html
│   ├── monday_init.sh          ← create this week's note from template
│   ├── friday_archive.sh       ← archive the week's note
│   ├── install_*.sh            ← launchd installers (idempotent)
│   ├── *.plist.tmpl            ← launchd agent templates (__LABEL__ rendered at install)
│   └── logs/                   ← per-job logs
├── Projects/                   ← active project workspaces
│   ├── _TEMPLATE/              ← copy this to start a new project
│   └── example-project/        ← worked example
├── Final_Products/             ← shipped, archived artifacts
└── Vault_Brain/                ← Obsidian LLM-wiki (open THIS folder in Obsidian)
    ├── CLAUDE.md               ← wiki schema (Layer 3)
    ├── README.md               ← how the vault works
    ├── wiki/                   ← one page per entity (LLM-maintained)
    ├── sources/                ← raw inputs (immutable)
    ├── concepts/  inbox/       ← staging → processed notes
    └── weekly-logs/  archive/  ← weekly notes
```

---

## Automation & health

`bootstrap.sh` can install three `launchd` agents (it asks first — default No). You can also run each installer directly later:

| Job | Installer | Schedule | What it does |
|-----|-----------|----------|--------------|
| **Daily ingest** | `System_Config/install_daily_ingest.sh` | daily 07:00 + at login | Reads new `Vault_Brain/sources/*.md` clips and files them into the wiki (one headless `claude -p` call per clip, content-hash dedup). |
| **Health check** | `System_Config/install_healthcheck.sh` | at login + every 4h | Probes all layers + doc currency, writes the status dashboard. |
| **Weekly notes** | `System_Config/install_friday_process.sh` | Fridays 19:00 | Writes a 1–2 sentence weekly summary into the Master Note and builds wiki cross-references. |

Run the health check on demand and open the dashboard:

```bash
bash System_Config/healthcheck.sh
open System_Config/status_page.html
```

`status_page.html` (and its `status.json` data) are **generated at runtime** into `System_Config/` — they are not part of the template and are git-ignored. Green = healthy; amber/red lists exactly what needs attention.

Start a fresh weekly note any time with `bash System_Config/monday_init.sh`. Full automation reference is in [`System_Config/README.md`](System_Config/README.md).

---

## Conventions & constraints

- **bash 3.2** — scripts run on stock macOS `/bin/bash`; no associative arrays, no `mapfile`, no bash 4+ syntax.
- **Relocatable** — nothing is hardcoded. Every script sources `System_Config/config.sh`, which derives `$WORKSPACE`, the vault paths, and the `launchd` label namespace from its own location and your environment. Clone the workspace anywhere and it just works. Override the label namespace with `export AGENT_WS_LABEL_PREFIX=com.acme.vaultbrain` before installing.
- **Docs stay current** — after any change to a script, agent, config, or the structure, update the governing doc in the same task. The health check flags a README that is older than the files it documents.
- **Append-only knowledge** — the wiki and weekly logs are create-or-append; agents never overwrite or delete vault content.
- **One `.mcp.json` per machine** — `.mcp.json.example` is tracked; your real `.mcp.json` (with any server URLs or credentials) is git-ignored. Never commit it.

---

## Pointers

- [`.AGENT.MD`](.AGENT.MD) — full workspace map + agent coordination matrix
- [`CLAUDE.md`](CLAUDE.md) — orchestrator rules and dispatch routing
- [`System_Config/README.md`](System_Config/README.md) — automation hub, installers, Full Disk Access setup
- [`Vault_Brain/README.md`](Vault_Brain/README.md) — how the knowledge vault works (weekly rhythm, clipper pipeline)
- `Vault_Brain/CLAUDE.md` — the LLM-wiki schema (read by agents first)

---

## License

MIT — see [LICENSE](LICENSE).
