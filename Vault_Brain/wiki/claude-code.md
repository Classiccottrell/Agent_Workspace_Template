---
title: Claude Code
type: technology
tags: [tooling, ai, cli, agent]
updated: 2025-01-01
---

## Summary
Claude Code is a command-line coding agent that runs in the terminal and operates directly on a local workspace. In this workspace it acts as the orchestrator that reads context, delegates to specialized subagents, and maintains the [[knowledge-management]] vault. It is the engine behind the automated ingest pipeline described in [[llm-wiki-pattern]].

## Key Facts
- Runs headlessly via `claude -p "<prompt>"`, which the daily ingest job uses to wikify one source clip per call.
- Reads a `CLAUDE.md` file at startup to load project instructions and operating rules.
- Supports tool gating — the ingest job runs with `--disallowedTools Bash` so the agent can only touch files, never the shell.
- Subagents live in `.claude/agents/` and are invoked by name rather than by pasting role text into a prompt.
- Pairs naturally with [[obsidian]]: Claude maintains the markdown wiki, Obsidian renders and links it.

## Connections
- [[obsidian]]
- [[knowledge-management]]
- [[llm-wiki-pattern]]

## Sources
- [[sources/2025-01-01_example-clip]]
