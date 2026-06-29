# Master Note

Weekly notes live in `weekly-logs/` as `YYYY-Www.md`. `monday_init.sh` creates them automatically; or run `bash System_Config/monday_init.sh` from the workspace root.

---

## Weekly Index
> `monday_init.sh` adds a row when each week starts; the Friday process fills the Summary. Newest rows append at the bottom.

| Week | Sprint | Q | Dates | Summary |
|------|--------|----|-------|---------|
<!-- WEEKLY-INDEX-INSERT -->

---

## Important Info
> Replace with your own reference details (contact addresses, account IDs, etc.).

- you@example.com

---

## Important Links
> Group your frequently used links by topic.

**Tooling**
- Claude usage: https://claude.ai/settings/usage

**Reference**
- (add your own bookmarks here)

---

## 📋 Markdown Snippets
> Copy-paste reference for syntax that's annoying to type. In reading mode, hover a block and click the copy icon to grab the raw text.

**Callouts (colored boxes)** — swap the type: `note`/`info` 🟦 · `tip`/`success` 🟩 · `warning` 🟨 · `danger`/`bug` 🟥 · `question` · `quote`
```text
> [!warning] Optional Title
> Body text goes on the next line.
```

**Collapsible callout** — append `-` to start folded (`+` to start open):
```text
> [!tip]- Click to expand
> Hidden until you click the title.
```

**Task checkboxes** (extended states render with the Tasks plugin / most themes):
```text
- [ ] open
- [x] done
- [/] in progress
- [-] dropped
- [?] question
```

**Code block with syntax highlighting** — language goes right after the fence:
````text
```js
const greeting = "hi"
```
````

**Inline styles:**
```text
==highlight==   **bold**   *italic*   ~~strikethrough~~   `inline code`
```

**Table:**
```text
| Column A | Column B |
|----------|----------|
| value    | value    |
```

**Footnote:**
```text
A claim that needs a source.[^1]

[^1]: The footnote text.
```

**Collapsible section (HTML — renders in reading mode):**
```text
<details><summary>Click to expand</summary>

Hidden content here.

</details>
```
