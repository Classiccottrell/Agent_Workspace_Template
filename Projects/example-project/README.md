# example-project — todo-cli

A tiny, illustrative project included with the template. It demonstrates the
project lifecycle (BRIEF → active work → move to Closed/). The "code"
here is intentionally a placeholder — the point is the structure, not the tool.

## What it would do

```sh
todo add "buy milk"   # -> added task #1
todo list             # -> [ ] #1 buy milk
todo done 1           # -> completed #1
todo --help           # -> usage
```

## Layout

```
example-project/
├── BRIEF.md     ← filled-in requirements + status (read this first)
├── README.md    ← you are here
├── active/      ← work in progress (see active/NOTES.md)
└── archive/     ← superseded or paused work
```

## Lifecycle this example illustrates

1. `BRIEF.md` is filled in (goal, non-goals, constraints, stack, acceptance, status).
2. Implementation happens under `active/`.
3. On completion, the archivist moves the whole project folder to `Closed/` via the
   Orchestrator and records it in `Closed/INDEX.md`.
