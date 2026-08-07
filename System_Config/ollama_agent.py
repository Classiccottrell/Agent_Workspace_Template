#!/usr/bin/env python3
"""
ollama_agent.py — stdlib-only tool-calling agent loop for the local `ollama`
provider in the Vault_Brain ingest pipeline (System_Config/run_agent.sh).

Daily ingest accepts one schema-constrained proposal and applies it locally.
Other jobs use five confined tools (read/list/grep/write/append) in an
/api/chat loop.

CLI (invoked from run_agent.sh's ollama branch):
  python3 ollama_agent.py "<prompt>" --vault "$VAULT" \
      --model "${AGENT_MODEL:-llama3.1:8b}" --host "${OLLAMA_HOST:-http://localhost:11434}" \
      --max-turns "${OLLAMA_MAX_TURNS:-8}" --http-timeout "${OLLAMA_HTTP_TIMEOUT:-300}"

Exit codes:
  0 - model finished (no more tool calls)
  1 - max-turns exhausted, an HTTP/JSON error mid-loop, or a config validation error
  2 - Ollama unreachable at preflight (fails fast, before the watchdog burns time)
  3 - configured model is not pulled on the Ollama host
  4 - OLLAMA_HOST is non-local and OLLAMA_ALLOW_REMOTE=1 was not set

Env:
  OLLAMA_DENY_PATHS      colon-separated, vault-relative — write tools may not
                          touch these (in addition to the hardcoded Master Note.md)
  OLLAMA_MAX_FILE_CHARS  cap on read_file output (default 20000)
  OLLAMA_NUM_CTX         /api/chat num_ctx option (default 8192)
  OLLAMA_MAX_NUM_CTX     ceiling num_ctx may be clamped to, incl. the dynamic
                          per-source size in propose_ingest (default 32768)
  OLLAMA_TEMPERATURE     /api/chat temperature option (default 0.1)
  OLLAMA_ALLOW_REMOTE    set to 1 to allow a non-localhost OLLAMA_HOST

--selftest: path-confinement + tool-primitive assertions against a throwaway
temp dir. No live Ollama server required.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request
import re
import tempfile
from datetime import date
from urllib.parse import urlparse

DEFAULT_MAX_FILE_CHARS = 20000
DEFAULT_MAX_NUM_CTX = 32768
DENY_ALWAYS = ("Master Note.md",)
GREP_MAX_HITS = 50
ENTITY_TYPES = {"concept", "person", "project", "technology", "org"}
SYSTEM_PROMPT = ("Be precise and rigorous — follow the exact schema and instructions given, "
                  "do not take shortcuts or leave placeholders, and do not guess at file "
                  "contents you haven't actually read.")
PROPOSAL_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "slug": {"type": "string"},
        "title": {"type": "string"},
        "type": {"type": "string", "enum": sorted(ENTITY_TYPES)},
        "tags": {"type": "array", "items": {"type": "string"}},
        "summary": {"type": "string"},
        "key_facts": {"type": "array", "items": {"type": "string"}},
        "connections": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["slug", "title", "type", "tags", "summary", "key_facts", "connections"],
}


class PathError(Exception):
    pass


def resolve_vault_path(vault_real, rel_path):
    """Resolve a vault-relative path, rejecting absolute paths and any
    escape (../, or symlink resolution landing outside the vault)."""
    if not rel_path or os.path.isabs(rel_path):
        raise PathError(f"path must be vault-relative, not absolute: {rel_path!r}")
    candidate = os.path.realpath(os.path.join(vault_real, rel_path))
    try:
        common = os.path.commonpath([vault_real, candidate])
    except ValueError:
        raise PathError(f"path escapes vault: {rel_path!r}")
    if common != vault_real:
        raise PathError(f"path escapes vault: {rel_path!r}")
    return candidate


def is_denied(vault_real, rel_path, deny_list):
    """True if rel_path (compared by realpath) falls under any deny-list
    entry — hardcoded Master Note.md plus the caller-supplied list."""
    try:
        candidate = resolve_vault_path(vault_real, rel_path)
    except PathError:
        return True
    for d in deny_list:
        d = (d or "").strip()
        if not d:
            continue
        try:
            denied_real = os.path.realpath(os.path.join(vault_real, d))
        except OSError:
            continue
        if candidate == denied_real or candidate.startswith(denied_real + os.sep):
            return True
    return False


# ── Tools ──────────────────────────────────────────────────────────────────

def tool_read_file(vault_real, rel_path, max_chars):
    p = resolve_vault_path(vault_real, rel_path)
    if not os.path.isfile(p):
        return f"ERROR: not a file: {rel_path}"
    with open(p, "r", errors="replace") as f:
        content = f.read()
    if len(content) > max_chars:
        content = content[:max_chars] + f"\n...[truncated at {max_chars} chars]"
    return content


def tool_list_dir(vault_real, rel_path):
    p = resolve_vault_path(vault_real, rel_path or ".")
    if not os.path.isdir(p):
        return f"ERROR: not a directory: {rel_path}"
    entries = sorted(os.listdir(p))
    return "\n".join(entries) if entries else "(empty)"


def tool_grep_vault(vault_real, query, rel_path):
    if not query:
        return "ERROR: query required"
    p = resolve_vault_path(vault_real, rel_path or "wiki")
    hits = []
    for root, dirs, files in os.walk(p):
        dirs.sort()
        for fn in sorted(files):
            if len(hits) >= GREP_MAX_HITS:
                break
            if not fn.endswith(".md"):
                continue
            fp = os.path.join(root, fn)
            try:
                with open(fp, "r", errors="replace") as f:
                    for i, line in enumerate(f, 1):
                        if query in line:
                            rel = os.path.relpath(fp, vault_real)
                            hits.append(f"{rel}:{i}:{line.strip()}")
                            if len(hits) >= GREP_MAX_HITS:
                                break
            except OSError:
                continue
        if len(hits) >= GREP_MAX_HITS:
            break
    return "\n".join(hits) if hits else "(no matches)"


def tool_write_file(vault_real, deny_list, rel_path, content):
    p = resolve_vault_path(vault_real, rel_path)
    if is_denied(vault_real, rel_path, deny_list):
        return f"ERROR: write denied (deny-list): {rel_path}"
    if os.path.exists(p):
        return f"ERROR: file already exists (write_file is create-only): {rel_path}"
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(content)
    return f"OK: created {rel_path}"


def tool_append_to_section(vault_real, deny_list, rel_path, heading, line):
    p = resolve_vault_path(vault_real, rel_path)
    if is_denied(vault_real, rel_path, deny_list):
        return f"ERROR: write denied (deny-list): {rel_path}"
    if not os.path.isfile(p):
        return f"ERROR: file does not exist: {rel_path}"
    with open(p, "r") as f:
        text = f.read()
    # Idempotency enforced structurally, not trusted to the model: exact
    # line text already present anywhere in the file -> no-op.
    if line and line in text:
        return "already present"
    heading_clean = heading.strip()
    if heading_clean.startswith("## "):
        heading_clean = heading_clean[3:].strip()
    heading_marker = "## " + heading_clean
    lines = text.split("\n")
    start_idx = None
    for i, l in enumerate(lines):
        if l.strip() == heading_marker:
            start_idx = i
            break
    if start_idx is None:
        return f"ERROR: heading not found: {heading_marker!r}"
    end_idx = len(lines)
    for j in range(start_idx + 1, len(lines)):
        if lines[j].startswith("## "):
            end_idx = j
            break
    # Back up over the '---' separator line (this vault's convention precedes
    # every heading) as well as blank lines, so insertion lands among the
    # section's actual content, above the separator, not in the narrow gap
    # between it and the next heading.
    insert_at = end_idx
    while insert_at > start_idx + 1 and lines[insert_at - 1].strip() in ("", "---"):
        insert_at -= 1
    new_lines = lines[:insert_at] + [line] + lines[insert_at:]
    with open(p, "w") as f:
        f.write("\n".join(new_lines))
    return f"OK: appended to {heading_marker} in {rel_path}"


TOOL_SCHEMAS = [
    {"type": "function", "function": {
        "name": "read_file",
        "description": "Read a vault-relative file's contents (capped).",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "vault-relative path"}},
            "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "list_dir",
        "description": "Non-recursive listing of a vault-relative directory.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "vault-relative path"}},
            "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "grep_vault",
        "description": "Literal substring search across .md files under a vault-relative dir (default wiki), capped at 50 hits.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "path": {"type": "string", "description": "vault-relative dir, default wiki"}},
            "required": ["query"]}}},
    {"type": "function", "function": {
        "name": "write_file",
        "description": "Create a new vault-relative file. Fails if the file already exists.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "content": {"type": "string"}},
            "required": ["path", "content"]}}},
    {"type": "function", "function": {
        "name": "append_to_section",
        "description": "Insert one line at the end of a named '## Heading' section (right before the next '## ' heading or EOF), idempotent on exact line text.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "heading": {"type": "string", "description": "section name without the '## ' prefix, e.g. 'Decisions', not '## Decisions'"},
            "line": {"type": "string"}},
            "required": ["path", "heading", "line"]}}},
]


def run_tool(name, tool_args, vault_real, deny_list, max_file_chars):
    try:
        if name == "read_file":
            return tool_read_file(vault_real, tool_args.get("path", ""), max_file_chars)
        elif name == "list_dir":
            return tool_list_dir(vault_real, tool_args.get("path", ""))
        elif name == "grep_vault":
            return tool_grep_vault(vault_real, tool_args.get("query", ""), tool_args.get("path", "wiki"))
        elif name == "write_file":
            return tool_write_file(vault_real, deny_list, tool_args.get("path", ""), tool_args.get("content", ""))
        elif name == "append_to_section":
            return tool_append_to_section(vault_real, deny_list, tool_args.get("path", ""),
                                           tool_args.get("heading", ""), tool_args.get("line", ""))
        else:
            return f"ERROR: unknown tool {name!r}"
    except PathError as e:
        return f"ERROR: {e}"
    except Exception as e:  # tool-level failure -> feed back to the model, don't crash the loop
        return f"ERROR: {type(e).__name__}: {e}"


# ── Config validation ──────────────────────────────────────────────────────

class ConfigError(Exception):
    pass


def _env_int(name, default, min_val, max_val):
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        val = int(raw)
    except ValueError:
        raise ConfigError(f"{name}={raw!r} must be an integer")
    if not (min_val <= val <= max_val):
        raise ConfigError(f"{name}={raw!r} must be between {min_val} and {max_val}")
    return val


def _env_float(name, default, min_val, max_val):
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        val = float(raw)
    except ValueError:
        raise ConfigError(f"{name}={raw!r} must be a number")
    if not (min_val <= val <= max_val):
        raise ConfigError(f"{name}={raw!r} must be between {min_val} and {max_val}")
    return val


def _check_range(label, val, min_val, max_val):
    if not (min_val <= val <= max_val):
        raise ConfigError(f"{label}={val} must be between {min_val} and {max_val}")


def validate_env_config():
    """Parse + range-check every OLLAMA_* numeric env var once, up front.
    Raises ConfigError naming the bad var/value on the first failure —
    callers turn that into one clear message + sys.exit(1), instead of a
    cryptic exception mid-run."""
    return {
        "num_ctx": _env_int("OLLAMA_NUM_CTX", 8192, 1, 1_000_000),
        "max_num_ctx": _env_int("OLLAMA_MAX_NUM_CTX", DEFAULT_MAX_NUM_CTX, 1024, 131072),
        "temperature": _env_float("OLLAMA_TEMPERATURE", 0.1, 0.0, 2.0),
        "max_file_chars": _env_int("OLLAMA_MAX_FILE_CHARS", DEFAULT_MAX_FILE_CHARS, 1, 10_000_000),
        # These two are also forwarded by run_agent.sh as --max-turns/--http-timeout
        # CLI args (so argparse would otherwise be the one to reject them, with its
        # own message and exit code 2 — which collides with "Ollama unreachable").
        # Validating the env var here, before argparse ever runs, gets the named
        # var/value message and exit 1 instead.
        "max_turns": _env_int("OLLAMA_MAX_TURNS", 8, 1, 1000),
        "http_timeout": _env_int("OLLAMA_HTTP_TIMEOUT", 300, 1, 86400),
    }


_ENV_CFG_CACHE = None


def get_env_cfg():
    """Lazily validated env config, cached for the process lifetime. main()
    validates eagerly (and exits clearly on failure) before any network call;
    direct callers (e.g. selftest) get the same validation on first use."""
    global _ENV_CFG_CACHE
    if _ENV_CFG_CACHE is None:
        _ENV_CFG_CACHE = validate_env_config()
    return _ENV_CFG_CACHE


def check_host_allowed(host):
    """This automation is local-only. Refuse a non-localhost OLLAMA_HOST
    unless the operator explicitly opts in — an accidentally-misconfigured
    remote host shouldn't silently receive vault content."""
    probe = host if "://" in host else f"http://{host}"
    hostname = (urlparse(probe).hostname or "").lower()
    if hostname in ("localhost", "127.0.0.1", "::1"):
        return
    if os.environ.get("OLLAMA_ALLOW_REMOTE") == "1":
        return
    print(f"[ollama_agent] REFUSING non-local OLLAMA_HOST={host!r} (host={hostname!r}); "
          f"set OLLAMA_ALLOW_REMOTE=1 to explicitly opt in.", file=sys.stderr)
    sys.exit(4)


def _tags_model_names(tags_json):
    names = set()
    for m in (tags_json.get("models") or []):
        if not isinstance(m, dict):
            continue
        for key in ("name", "model"):
            if m.get(key):
                names.add(m[key])
    return names


def _model_available(configured, names):
    if configured in names:
        return True
    if ":" not in configured:
        return any(n.split(":")[0] == configured for n in names)
    return f"{configured}:latest" in names


# ── Ollama transport ──────────────────────────────────────────────────────

def preflight(host, model, timeout):
    try:
        req = urllib.request.Request(host.rstrip("/") + "/api/tags")
        with urllib.request.urlopen(req, timeout=min(timeout, 10)) as resp:
            body = resp.read().decode("utf-8")
    except Exception as e:
        print(f"[ollama_agent] OLLAMA UNREACHABLE at {host}: {e}", file=sys.stderr)
        sys.exit(2)
    try:
        names = _tags_model_names(json.loads(body))
    except Exception as e:
        print(f"[ollama_agent] OLLAMA UNREACHABLE at {host}: unparseable /api/tags response: {e}",
              file=sys.stderr)
        sys.exit(2)
    if not _model_available(model, names):
        print(f"[ollama_agent] MODEL NOT FOUND: {model!r} is not pulled on {host}. "
              f"Run: ollama pull {model}", file=sys.stderr)
        sys.exit(3)


def chat(host, model, messages, timeout):
    cfg = get_env_cfg()
    payload = {
        "model": model,
        "messages": messages,
        "tools": TOOL_SCHEMAS,
        "stream": False,
        "options": {
            "num_ctx": min(cfg["num_ctx"], cfg["max_num_ctx"]),
            "temperature": cfg["temperature"],
        },
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(host.rstrip("/") + "/api/chat", data=data,
                                  headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read().decode("utf-8")
    return json.loads(body)


def propose_ingest(host, model, source_path, source, existing_slugs, timeout):
    prompt = """Return one JSON object matching the supplied schema. Identify the ONE primary
entity in the source. Reuse an existing slug when it names the same entity. Slugs, tags,
and connection slugs must be lowercase letters/numbers/hyphens. Summary must be 2-4
sentences. Facts must be atomic and supported by this source. No markdown or commentary.

Source path: %s
Existing wiki slugs: %s

SOURCE BEGIN
%s
SOURCE END""" % (source_path, ", ".join(existing_slugs), source)
    cfg = get_env_cfg()
    num_ctx = min(max(cfg["num_ctx"], len(source) // 3 + 4096), cfg["max_num_ctx"])
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": prompt}],
        "format": PROPOSAL_SCHEMA,
        "stream": False,
        "options": {
            "num_ctx": num_ctx,
            "temperature": 0,
        },
    }
    req = urllib.request.Request(host.rstrip("/") + "/api/chat",
        data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        result = json.loads(resp.read().decode())
    if result.get("done") is not True or result.get("done_reason") not in (None, "stop"):
        raise ValueError("truncated model response")
    return json.loads((result.get("message") or {}).get("content", ""))


def validate_proposal(p):
    if not isinstance(p, dict) or set(p) != set(PROPOSAL_SCHEMA["required"]):
        raise ValueError("proposal schema mismatch")
    slug_re = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
    if not slug_re.fullmatch(p["slug"]) or p["type"] not in ENTITY_TYPES:
        raise ValueError("invalid slug or entity type")
    for key in ("title", "summary"):
        if not isinstance(p[key], str) or not p[key].strip():
            raise ValueError(f"invalid {key}")
    for key in ("tags", "key_facts", "connections"):
        if not isinstance(p[key], list) or not all(isinstance(v, str) and v.strip() for v in p[key]):
            raise ValueError(f"invalid {key}")
    if not p["key_facts"]:
        raise ValueError("at least one key fact required")
    if not all(slug_re.fullmatch(v) for v in p["connections"]):
        raise ValueError("invalid connection slug")
    if not all(slug_re.fullmatch(v) for v in p["tags"]):
        raise ValueError("invalid tag")
    return p


def append_unique_to_section(text, heading, lines):
    marker = "## " + heading
    start = text.find(marker)
    if start < 0:
        raise ValueError(f"missing section: {heading}")
    end = text.find("\n## ", start + len(marker))
    end = len(text) if end < 0 else end
    additions = [line for line in lines if line not in text]
    if not additions:
        return text
    # This vault's convention is a standalone '---' separator line before the
    # next heading. Insert above that separator (among the section's actual
    # content), not below it. Use the LAST such line in range so nested rules
    # inside content don't fool this; fall back to `end` (old behavior) if no
    # separator exists between this section and the next heading.
    insert_at = end
    for m in re.finditer(r"\n---\n", text[start:end]):
        insert_at = start + m.start()
    return text[:insert_at].rstrip() + "\n" + "\n".join(additions) + "\n\n" + text[insert_at:].lstrip("\n")


def render_weekly(template, year, week, today):
    values = {"{{WEEK_NUM}}": week, "{{YEAR}}": year, "{{WEEK_LABEL}}": f"Week {week}",
              "{{SPRINT}}": week, "{{QUARTER}}": str((int(today[5:7]) - 1) // 3 + 1),
              "{{DATE_START}}": today, "{{DATE_END}}": today, "{{INIT_DATE}}": today}
    for old, new in values.items():
        template = template.replace(old, new)
    return template


def apply_proposal(vault_real, proposal, source_rel, weekly_rel, today):
    p = validate_proposal(proposal)
    src_link = source_rel[:-3] if source_rel.endswith(".md") else source_rel
    page_rel = f"wiki/{p['slug']}.md"
    page_path = resolve_vault_path(vault_real, page_rel)
    index_path = resolve_vault_path(vault_real, "wiki/_index.md")
    weekly_path = resolve_vault_path(vault_real, weekly_rel)
    index = open(index_path).read()
    if os.path.exists(page_path):
        page = open(page_path).read()
        if not re.match(r"^---\ntitle: .+\ntype: (concept|person|project|technology|org)\ntags: \[.*\]\nupdated: \d{4}-\d{2}-\d{2}\n---\n", page):
            raise ValueError("existing page has invalid frontmatter")
        for heading in ("Summary", "Key Facts", "Connections", "Sources"):
            if f"## {heading}" not in page:
                raise ValueError(f"existing page missing {heading}")
        page = append_unique_to_section(page, "Key Facts", [f"- {v}" for v in p["key_facts"]])
        page = append_unique_to_section(page, "Connections", [f"- [[{v}]]" for v in p["connections"]])
        page = append_unique_to_section(page, "Sources", [f"- [[{src_link}]]"])
        page = re.sub(r"(?m)^updated: .*?$", f"updated: {today}", page, count=1)
    else:
        tags = ", ".join(p["tags"])
        facts = "\n".join(f"- {v}" for v in p["key_facts"])
        connections = "\n".join(f"- [[{v}]]" for v in p["connections"])
        page = (f"---\ntitle: {p['title']}\ntype: {p['type']}\ntags: [{tags}]\nupdated: {today}\n---\n\n"
                f"## Summary\n{p['summary'].strip()}\n\n## Key Facts\n{facts}\n\n"
                f"## Connections\n{connections}\n\n## Sources\n- [[{src_link}]]\n")
    index = append_unique_to_section(index, "Pages", [f"| [[{p['slug']}]] | {p['type']} | {today} |"])
    index = append_unique_to_section(index, "Sources", [f"| [[{src_link}]] | {today} |"])
    if os.path.exists(weekly_path):
        weekly = open(weekly_path).read()
    else:
        year, week = re.fullmatch(r"weekly-logs/(\d{4})-W(\d{2})\.md", weekly_rel).groups()
        weekly = render_weekly(open(resolve_vault_path(vault_real, "Weekly_Note_Template.md")).read(), year, week, today)
    queue_line = f"- {today}: ingested {os.path.basename(source_rel)} -> [[{page_rel[:-3]}]]"
    weekly = append_unique_to_section(weekly, "Claude Sessions", [queue_line])

    originals = {page_path: open(page_path).read() if os.path.exists(page_path) else None,
                 index_path: open(index_path).read(), weekly_path: open(weekly_path).read() if os.path.exists(weekly_path) else None}
    pending_tmp = None
    try:
        for path, content in ((page_path, page), (index_path, index), (weekly_path, weekly)):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            fd, pending_tmp = tempfile.mkstemp(dir=os.path.dirname(path), text=True)
            with os.fdopen(fd, "w") as f:
                f.write(content)
            os.chmod(pending_tmp, os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o644)
            os.replace(pending_tmp, path)
            pending_tmp = None
        if verify_ingest(vault_real, source_rel, weekly_rel, today) != p["slug"]:
            raise ValueError("missing ingest postcondition")
    except Exception:
        if pending_tmp and os.path.exists(pending_tmp):
            os.unlink(pending_tmp)
        for path, content in originals.items():
            if content is None:
                if os.path.exists(path): os.unlink(path)
            else:
                with open(path, "w") as f: f.write(content)
        raise
    return page_rel


def verify_ingest(vault_real, source_rel, weekly_rel, today):
    src_link = source_rel[:-3] if source_rel.endswith(".md") else source_rel
    pages = []
    for name in os.listdir(resolve_vault_path(vault_real, "wiki")):
        if name.startswith("_") or not name.endswith(".md"):
            continue
        path = resolve_vault_path(vault_real, "wiki/" + name)
        text = open(path).read()
        if f"[[{src_link}]]" in text:
            pages.append((name[:-3], text))
    if len(pages) != 1:
        raise ValueError("source must be cited by exactly one entity page")
    slug, page = pages[0]
    if not re.match(r"^---\ntitle: .+\ntype: (concept|person|project|technology|org)\ntags: \[.*\]\nupdated: \d{4}-\d{2}-\d{2}\n---\n", page):
        raise ValueError("invalid page frontmatter")
    if not all(f"## {heading}" in page for heading in ("Summary", "Key Facts", "Connections", "Sources")):
        raise ValueError("missing page section")
    index = open(resolve_vault_path(vault_real, "wiki/_index.md")).read()
    weekly = open(resolve_vault_path(vault_real, weekly_rel)).read()
    line = f"- {today}: ingested {os.path.basename(source_rel)} -> [[wiki/{slug}]]"
    if f"[[{slug}]]" not in index or f"[[{src_link}]]" not in index or line not in weekly:
        raise ValueError("missing index or weekly postcondition")
    return slug


def ingest_once(vault_real, model, host, timeout):
    source_rel = os.environ["OLLAMA_INGEST_NOTE"]
    weekly_rel = os.environ["OLLAMA_WEEKLY_NOTE"]
    today = os.environ.get("OLLAMA_INGEST_DATE", date.today().isoformat())
    source = open(resolve_vault_path(vault_real, source_rel), errors="replace").read()
    slugs = sorted(os.path.splitext(v)[0] for v in os.listdir(resolve_vault_path(vault_real, "wiki"))
                   if v.endswith(".md") and not v.startswith("_"))
    proposal = propose_ingest(host, model, source_rel, source, slugs, timeout)
    page = apply_proposal(vault_real, proposal, source_rel, weekly_rel, today)
    print(f"[ollama_agent] applied validated proposal to {page}", file=sys.stderr)


def main_loop(prompt, vault_real, deny_list, model, host, max_turns, http_timeout, max_file_chars):
    check_host_allowed(host)
    preflight(host, model, http_timeout)
    if os.environ.get("OLLAMA_INGEST_NOTE"):
        try:
            ingest_once(vault_real, model, host, http_timeout)
        except Exception as e:
            print(f"[ollama_agent] ingest rejected: {type(e).__name__}: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": prompt}]
    turn = 0
    while turn < max_turns:
        turn += 1
        print(f"[ollama_agent] turn {turn}/{max_turns}", file=sys.stderr)
        try:
            resp = chat(host, model, messages, http_timeout)
        except Exception as e:
            print(f"[ollama_agent] HTTP/JSON error: {type(e).__name__}: {e}", file=sys.stderr)
            sys.exit(1)
        msg = resp.get("message", {}) or {}
        messages.append(msg)
        tool_calls = msg.get("tool_calls") or []
        if not tool_calls:
            content = (msg.get("content") or "")[:2000]
            print(f"[ollama_agent] done (no tool calls). final content: {content}", file=sys.stderr)
            sys.exit(0)
        for tc in tool_calls:
            fn = tc.get("function", {}) or {}
            name = fn.get("name", "")
            raw_args = fn.get("arguments", {})
            if isinstance(raw_args, str):
                try:
                    raw_args = json.loads(raw_args) if raw_args else {}
                except json.JSONDecodeError as e:
                    result = f"ERROR: malformed tool-call JSON: {e}"
                    print(f"[ollama_agent] tool call: {name} -> {result}", file=sys.stderr)
                    messages.append({"role": "tool", "name": name, "content": result})
                    continue
            if not isinstance(raw_args, dict):
                raw_args = {}
            result = run_tool(name, raw_args, vault_real, deny_list, max_file_chars)
            print(f"[ollama_agent] tool call: {name}({raw_args}) -> {str(result)[:200]}", file=sys.stderr)
            messages.append({"role": "tool", "name": name, "content": result})
    print(f"[ollama_agent] max turns ({max_turns}) exhausted", file=sys.stderr)
    sys.exit(1)


# ── Selftest ───────────────────────────────────────────────────────────────

def run_selftest():
    import shutil
    import tempfile

    global _ENV_CFG_CACHE
    tmpdir = tempfile.mkdtemp(prefix="ollama_agent_selftest_")
    ok = True

    def check(desc, cond):
        nonlocal ok
        print(f"[selftest] {'ok' if cond else 'FAIL'}: {desc}")
        if not cond:
            ok = False

    try:
        vault_real = os.path.realpath(tmpdir)
        os.makedirs(os.path.join(vault_real, "wiki"))
        os.makedirs(os.path.join(vault_real, "sources"))
        with open(os.path.join(vault_real, "wiki", "test.md"), "w") as f:
            f.write("---\ntitle: Test\n---\n\n## Summary\nhi\n\n## Connections\n\n## Sources\n")
        with open(os.path.join(vault_real, "wiki", "_index.md"), "w") as f:
            f.write("# Wiki Index\n\n## Pages\n\n| Page | Type | Updated |\n|---|---|---|\n\n## Sources\n\n| Source | Clipped |\n|---|---|\n")
        with open(os.path.join(vault_real, "Weekly_Note_Template.md"), "w") as f:
            f.write("# W{{WEEK_NUM}} — {{WEEK_LABEL}}\n\n## Claude Sessions\n-\n\n## Decisions\n")
        with open(os.path.join(vault_real, "sources", "new.md"), "w") as f:
            f.write("x" * 25001)

        deny_list = list(DENY_ALWAYS)

        try:
            resolve_vault_path(vault_real, "/etc/passwd")
            check("absolute path rejected", False)
        except PathError:
            check("absolute path rejected", True)

        try:
            resolve_vault_path(vault_real, "../../etc/passwd")
            check("../ escape rejected", False)
        except PathError:
            check("../ escape rejected", True)

        try:
            p = resolve_vault_path(vault_real, "wiki/test.md")
            check("in-vault path resolves", p == os.path.realpath(os.path.join(vault_real, "wiki", "test.md")))
        except PathError:
            check("in-vault path resolves", False)

        outside = tempfile.mkdtemp(prefix="ollama_agent_selftest_outside_")
        try:
            with open(os.path.join(outside, "secret.md"), "w") as f:
                f.write("secret")
            link = os.path.join(vault_real, "escape_link.md")
            os.symlink(os.path.join(outside, "secret.md"), link)
            try:
                resolve_vault_path(vault_real, "escape_link.md")
                check("symlink escape rejected", False)
            except PathError:
                check("symlink escape rejected", True)
        finally:
            shutil.rmtree(outside, ignore_errors=True)

        check("Master Note.md denied", is_denied(vault_real, "Master Note.md", deny_list))

        deny_list2 = deny_list + ["sources"]
        check("ambient deny path denied", is_denied(vault_real, "sources/clip.md", deny_list2))
        check("non-denied path allowed", not is_denied(vault_real, "wiki/other.md", deny_list2))

        r = tool_write_file(vault_real, [], "wiki/newpage.md", "content")
        check("write_file creates new file", r.startswith("OK") and
              os.path.exists(os.path.join(vault_real, "wiki", "newpage.md")))
        r2 = tool_write_file(vault_real, [], "wiki/newpage.md", "other content")
        check("write_file refuses existing file", r2.startswith("ERROR"))

        r3 = tool_append_to_section(vault_real, [], "wiki/test.md", "Connections", "- [[foo]]")
        check("append_to_section appends OK", "OK" in r3)
        with open(os.path.join(vault_real, "wiki", "test.md")) as f:
            body = f.read()
        idx_conn = body.find("## Connections")
        idx_src = body.find("## Sources")
        idx_link = body.find("- [[foo]]")
        check("appended line lands before next heading", idx_conn < idx_link < idx_src)

        r4 = tool_append_to_section(vault_real, [], "wiki/test.md", "Connections", "- [[foo]]")
        check("append_to_section is idempotent (no duplicate)", r4 == "already present")

        # Regression: 2026-W31.md corruption. This vault's convention is a
        # standalone '---' line before every '## heading'; appends must land
        # above it (in the section's content), not in the gap below it.
        with open(os.path.join(vault_real, "weekly-sep-test.md"), "w") as f:
            f.write("## Claude Sessions\n> Auto-appended after each AI work session.\n-\n\n---\n\n## Decisions\n")
        tool_append_to_section(vault_real, [], "weekly-sep-test.md", "Claude Sessions", "- 2026-07-30: ingested one.md -> [[wiki/one]]")
        tool_append_to_section(vault_real, [], "weekly-sep-test.md", "Claude Sessions", "- 2026-07-31: ingested two.md -> [[wiki/two]]")
        with open(os.path.join(vault_real, "weekly-sep-test.md")) as f:
            sep_body = f.read()
        sep_lines = sep_body.rstrip("\n").split("\n")
        heading_i = sep_lines.index("## Decisions")
        check("tool_append_to_section: '---' stays last line before next heading after 2 appends",
              sep_lines[heading_i - 2] == "---" and sep_lines[heading_i - 1] == "" and
              sep_body.count("\n---\n") == 1 and
              "- 2026-07-30: ingested one.md -> [[wiki/one]]" in sep_body and
              "- 2026-07-31: ingested two.md -> [[wiki/two]]" in sep_body)

        sep_text = "## Claude Sessions\n> Auto-appended after each AI work session.\n-\n\n---\n\n## Decisions\n"
        sep_text = append_unique_to_section(sep_text, "Claude Sessions", ["- 2026-07-30: ingested one.md -> [[wiki/one]]"])
        sep_text = append_unique_to_section(sep_text, "Claude Sessions", ["- 2026-07-31: ingested two.md -> [[wiki/two]]"])
        sep2_lines = sep_text.rstrip("\n").split("\n")
        heading2_i = sep2_lines.index("## Decisions")
        check("append_unique_to_section: '---' stays last line before next heading after 2 appends",
              sep2_lines[heading2_i - 2] == "---" and sep2_lines[heading2_i - 1] == "" and
              sep_text.count("\n---\n") == 1 and
              "- 2026-07-30: ingested one.md -> [[wiki/one]]" in sep_text and
              "- 2026-07-31: ingested two.md -> [[wiki/two]]" in sep_text)

        r5 = tool_write_file(vault_real, ["Master Note.md"], "Master Note.md", "x")
        check("write_file denies Master Note.md", r5.startswith("ERROR"))

        proposal = {"slug": "new-entity", "title": "New Entity", "type": "concept",
                    "tags": ["test"], "summary": "A supported summary. It has context.",
                    "key_facts": ["First fact."], "connections": ["related-entity"]}
        captured = {}
        original_urlopen = urllib.request.urlopen

        class FakeResponse:
            def __init__(self, result):
                self.result = result
            def __enter__(self):
                return self
            def __exit__(self, *_):
                return False
            def read(self):
                return json.dumps(self.result).encode()

        def fake_urlopen(req, timeout=None):
            captured.update(json.loads(req.data.decode()))
            return FakeResponse({"done": True, "done_reason": "stop",
                                 "message": {"content": json.dumps(proposal)}})

        urllib.request.urlopen = fake_urlopen
        try:
            transported = propose_ingest("http://test", "test", "sources/new.md", "x" * 25001, [], 1)
            check(">20k source reaches proposal transport", transported == proposal and
                  captured["messages"][0] == {"role": "system", "content": SYSTEM_PROMPT} and
                  "x" * 25001 in captured["messages"][1]["content"] and
                  captured["options"]["num_ctx"] > 8192)

            # OLLAMA_MAX_NUM_CTX ceiling clamps the dynamic per-source num_ctx.
            saved_cache = _ENV_CFG_CACHE
            os.environ["OLLAMA_MAX_NUM_CTX"] = "20000"
            _ENV_CFG_CACHE = None
            try:
                propose_ingest("http://test", "test", "sources/new.md", "x" * 300000, [], 1)
                check("dynamic num_ctx clamped to OLLAMA_MAX_NUM_CTX", captured["options"]["num_ctx"] == 20000)
            finally:
                del os.environ["OLLAMA_MAX_NUM_CTX"]
                _ENV_CFG_CACHE = saved_cache

            urllib.request.urlopen = lambda *_a, **_k: FakeResponse(
                {"done": True, "done_reason": "stop", "message": {"content": "{bad"}})
            try:
                propose_ingest("http://test", "test", "sources/new.md", "source", [], 1)
                check("malformed transport JSON rejected", False)
            except json.JSONDecodeError:
                check("malformed transport JSON rejected", True)
            urllib.request.urlopen = lambda *_a, **_k: FakeResponse(
                {"done": True, "done_reason": "length", "message": {"content": json.dumps(proposal)}})
            try:
                propose_ingest("http://test", "test", "sources/new.md", "source", [], 1)
                check("truncated proposal rejected", False)
            except ValueError:
                check("truncated proposal rejected", True)
        finally:
            urllib.request.urlopen = original_urlopen

        # ── Config validation ────────────────────────────────────────────
        saved_cache = _ENV_CFG_CACHE
        for bad_var, bad_val in (("OLLAMA_NUM_CTX", "not-a-number"),
                                  ("OLLAMA_TEMPERATURE", "5"),
                                  ("OLLAMA_MAX_FILE_CHARS", "-1"),
                                  ("OLLAMA_MAX_NUM_CTX", "0"),
                                  ("OLLAMA_MAX_TURNS", "abc"),
                                  ("OLLAMA_HTTP_TIMEOUT", "-5")):
            os.environ[bad_var] = bad_val
            try:
                validate_env_config()
                check(f"{bad_var}={bad_val} rejected", False)
            except ConfigError:
                check(f"{bad_var}={bad_val} rejected", True)
            finally:
                del os.environ[bad_var]
        _ENV_CFG_CACHE = saved_cache

        try:
            _check_range("OLLAMA_MAX_TURNS", 0, 1, 1000)
            check("non-positive OLLAMA_MAX_TURNS rejected", False)
        except ConfigError:
            check("non-positive OLLAMA_MAX_TURNS rejected", True)

        # ── Host guard ───────────────────────────────────────────────────
        try:
            check_host_allowed("http://localhost:11434")
            check("localhost host allowed", True)
        except SystemExit:
            check("localhost host allowed", False)
        try:
            check_host_allowed("http://127.0.0.1:11434")
            check("127.0.0.1 host allowed", True)
        except SystemExit:
            check("127.0.0.1 host allowed", False)
        try:
            check_host_allowed("http://example.com:11434")
            check("remote host refused without opt-in", False)
        except SystemExit as e:
            check("remote host refused without opt-in", e.code == 4)
        os.environ["OLLAMA_ALLOW_REMOTE"] = "1"
        try:
            check_host_allowed("http://example.com:11434")
            check("remote host allowed with OLLAMA_ALLOW_REMOTE=1", True)
        except SystemExit:
            check("remote host allowed with OLLAMA_ALLOW_REMOTE=1", False)
        finally:
            del os.environ["OLLAMA_ALLOW_REMOTE"]

        # ── preflight: unreachable / model-missing / model-present ────────
        try:
            urllib.request.urlopen = lambda *_a, **_k: (_ for _ in ()).throw(OSError("refused"))
            try:
                preflight("http://test", "llama3.1:8b", 1)
                check("preflight exits on unreachable host", False)
            except SystemExit as e:
                check("preflight exits on unreachable host", e.code == 2)

            urllib.request.urlopen = lambda *_a, **_k: FakeResponse(
                {"models": [{"name": "other-model:latest", "model": "other-model:latest"}]})
            try:
                preflight("http://test", "llama3.1:8b", 1)
                check("preflight exits distinctly when model missing", False)
            except SystemExit as e:
                check("preflight exits distinctly when model missing", e.code == 3)

            urllib.request.urlopen = lambda *_a, **_k: FakeResponse(
                {"models": [{"name": "llama3.1:8b", "model": "llama3.1:8b"}]})
            try:
                preflight("http://test", "llama3.1:8b", 1)
                check("preflight passes when model present", True)
            except SystemExit:
                check("preflight passes when model present", False)

            urllib.request.urlopen = lambda *_a, **_k: FakeResponse(
                {"models": [{"name": "llama3.1:8b", "model": "llama3.1:8b"}]})
            try:
                preflight("http://test", "llama3.1", 1)
                check("preflight matches bare model name against tagged model", True)
            except SystemExit:
                check("preflight matches bare model name against tagged model", False)
        finally:
            urllib.request.urlopen = original_urlopen

        with open(os.path.join(vault_real, "wiki", "_index.md"), "a") as f:
            f.write("| [[sources/new]] | 2026-07-31 |\n")
        try:
            verify_ingest(vault_real, "sources/new.md", "weekly-logs/2026-W31.md", "2026-07-31")
            check("verification rejects index-only source", False)
        except ValueError:
            check("verification rejects index-only source", True)
        original_replace = os.replace
        replace_calls = 0
        def failing_replace(src, dst):
            nonlocal replace_calls
            replace_calls += 1
            if replace_calls == 2:
                raise OSError("synthetic replace failure")
            original_replace(src, dst)
        os.replace = failing_replace
        try:
            try:
                apply_proposal(vault_real, proposal, "sources/new.md", "weekly-logs/2026-W31.md", "2026-07-31")
                check("failed apply raises", False)
            except OSError:
                leftovers = [name for root, _dirs, files in os.walk(vault_real)
                             for name in files if name.startswith("tmp")]
                check("failed apply rolls back and cleans temp", not leftovers and
                      not os.path.exists(os.path.join(vault_real, "wiki", "new-entity.md")))
        finally:
            os.replace = original_replace
        apply_proposal(vault_real, proposal, "sources/new.md", "weekly-logs/2026-W31.md", "2026-07-31")
        new_page = open(os.path.join(vault_real, "wiki", "new-entity.md")).read()
        check("new page has schema and citation", new_page.startswith("---\ntitle: New Entity\n") and
              "[[sources/new]]" in new_page)
        check(">20k source remains intact", len(open(os.path.join(vault_real, "sources", "new.md")).read()) == 25001)
        apply_proposal(vault_real, proposal, "sources/new.md", "weekly-logs/2026-W31.md", "2026-07-31")
        check("duplicate ingest is idempotent", open(os.path.join(vault_real, "wiki", "new-entity.md")).read().count("[[sources/new]]") == 1)
        with open(os.path.join(vault_real, "sources", "update.md"), "w") as f:
            f.write("update")
        proposal["key_facts"] = ["Second fact."]
        apply_proposal(vault_real, proposal, "sources/update.md", "weekly-logs/2026-W31.md", "2026-07-31")
        check("existing page appends fact and source", "Second fact." in open(os.path.join(vault_real, "wiki", "new-entity.md")).read() and
              "[[sources/update]]" in open(os.path.join(vault_real, "wiki", "new-entity.md")).read())
        try:
            validate_proposal({"slug": "NOT VALID"})
            check("malformed proposal rejected", False)
        except ValueError:
            check("malformed proposal rejected", True)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    print("[selftest] " + ("ALL PASS" if ok else "FAILURES PRESENT"))
    return 0 if ok else 1


def main():
    # Validate env-sourced numeric config before argparse: run_agent.sh passes
    # OLLAMA_MAX_TURNS/OLLAMA_HTTP_TIMEOUT through as CLI args, so garbage there
    # would otherwise surface as argparse's own cryptic error (and its exit
    # code 2 collides with our documented "Ollama unreachable" code).
    global _ENV_CFG_CACHE
    try:
        _ENV_CFG_CACHE = validate_env_config()
    except ConfigError as e:
        print(f"[ollama_agent] CONFIG ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    ap = argparse.ArgumentParser()
    ap.add_argument("prompt", nargs="?", default="")
    ap.add_argument("--vault", default=".")
    ap.add_argument("--model", default="llama3.1:8b")
    ap.add_argument("--host", default="http://localhost:11434")
    ap.add_argument("--max-turns", type=int, default=8)
    ap.add_argument("--http-timeout", type=int, default=300)
    ap.add_argument("--verify-note")
    ap.add_argument("--weekly-note")
    ap.add_argument("--ingest-date")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        sys.exit(run_selftest())

    try:
        _check_range("OLLAMA_MAX_TURNS", args.max_turns, 1, 1000)
        _check_range("OLLAMA_HTTP_TIMEOUT", args.http_timeout, 1, 86400)
    except ConfigError as e:
        print(f"[ollama_agent] CONFIG ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    vault_real = os.path.realpath(args.vault)
    if args.verify_note:
        try:
            print(verify_ingest(vault_real, args.verify_note, args.weekly_note,
                                args.ingest_date or date.today().isoformat()))
        except Exception as e:
            print(f"[ollama_agent] verification failed: {e}", file=sys.stderr)
            sys.exit(1)
        return

    if not args.prompt:
        print("[ollama_agent] ERROR: prompt argument required", file=sys.stderr)
        sys.exit(1)

    deny_list = list(DENY_ALWAYS)
    ambient = os.environ.get("OLLAMA_DENY_PATHS", "")
    if ambient:
        deny_list += ambient.split(":")
    max_file_chars = _ENV_CFG_CACHE["max_file_chars"]

    main_loop(args.prompt, vault_real, deny_list, args.model, args.host,
              args.max_turns, args.http_timeout, max_file_chars)


if __name__ == "__main__":
    main()
