# BRIEF — example-project (todo-cli)

> Illustrative example. Shows a fully filled-in brief for a tiny project so you
> can see what "done" looks like. Replace with your own when you start real work.

## Goal
A minimal command-line todo tool. A user can add a task, list open tasks, and
mark a task done. Single file, no external dependencies.

## Non-Goals
- No database — tasks live in a plain text file.
- No due dates, tags, priorities, or sync.
- No GUI or web interface.

## Constraints
- Must run with only the language runtime installed (no package install step).
- Tasks persisted to a human-readable file in the user's home directory.
- Commands respond in under 100 ms for lists up to 1,000 tasks.

## Stack
- A single scripting language of your choice (e.g. Python 3 or Node.js).
- Standard library only.

## Acceptance Criteria
- [x] `todo add "buy milk"` appends a task and prints its id.
- [x] `todo list` prints open tasks with ids.
- [x] `todo done <id>` marks a task complete.
- [x] State survives between runs (persisted to disk).
- [x] `todo --help` documents all commands.

## Status
**shipped**

| Date       | Update                                            |
|------------|---------------------------------------------------|
| YYYY-MM-DD | Project created from _TEMPLATE.                   |
| YYYY-MM-DD | add/list/done implemented; acceptance met.        |
| YYYY-MM-DD | Shipped — artifact handed to Final_Products/.     |
