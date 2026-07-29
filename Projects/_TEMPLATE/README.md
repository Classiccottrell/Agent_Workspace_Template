# Starting a New Project

`_TEMPLATE/` is the canonical skeleton for a new project. Do not edit it in place —
copy it.

## Quick start

```sh
# from the workspace root
cp -R Projects/_TEMPLATE "Projects/my-new-project"
```

Then:

1. Open `Projects/my-new-project/BRIEF.md` and fill in every section
   (goal, non-goals, constraints, stack, acceptance criteria, status).
2. Update `README.md` with how to run/build the project.
3. Add a row for the project to `Projects/.AGENT.MD` under **Active Projects**.
4. Put work-in-progress under `active/`; move superseded work to `archive/`.

## Layout

```
my-new-project/
├── BRIEF.md     ← requirements + status (start here)
├── README.md    ← how to run / build
├── active/      ← work in progress
└── archive/     ← superseded or paused work
```

> `archive/` is for superseded work-in-progress *within* the project (separate from
> moving the whole project folder to `Closed/` when the project is done).

When the project ships or is otherwise done, the archivist moves the whole
`Projects/<name>/` folder to `Closed/<name>/` (tagged with an outcome:
`shipped | paused | superseded | abandoned`).
