# BRIEF — example (hello.sh)

> Toy project for WELCOME.md's first delegation walkthrough. Safe to delete.

## Goal
Add a `--greet` flag to `hello.sh` that prints a greeting using the caller's
name instead of the default "World" line.

## Non-Goals
- No arg parsing library — plain bash `case`/`if` is enough.
- No other flags, config files, or persistence.

## Constraints
- Must stay a single bash file, runnable with only `/bin/bash`.
- Must not break `./hello.sh` with no args (still prints the two default lines).

## Stack
- bash (stock macOS `/bin/bash`, no bash 4+ features)

## Acceptance Criteria
- [ ] `./hello.sh` still prints "hello from the Agent Workspace" and "hi, World".
- [ ] `./hello.sh --greet Matt` prints a greeting containing "Matt".
- [ ] `./hello.sh --help` documents the flag.

## Status
**planning**

| Date       | Update            |
|------------|-------------------|
| 2026-07-09 | Example seeded.   |
