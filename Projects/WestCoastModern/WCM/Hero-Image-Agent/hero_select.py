#!/usr/bin/env python3
"""West Coast Modern — two-stage hero-image selection engine.

Stage 1 (triage): score every image 0-60 for WCM hero fit with a cheap, fast
model (one image per call, downscaled, run in parallel).

Stage 2 (hero pick): send the top-N highest-scoring images at full quality to a
strong model with SKILL.md as the system prompt, and ask for the full Hero
Report.

Manual use:
    python3 hero_select.py /path/to/PropertyName [--top 12] [--workers 5]

The watcher (watch_folder.py) imports process_folder() / make_client() from here.

Outputs written into the property folder:
    triage_scores.csv  — every image: file, score, isExterior, note (sorted desc)
    hero_report.md     — the Stage-2 report
"""
from __future__ import annotations

import argparse
import base64
import csv
import io
import json
import os
import random
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from pathlib import Path

import anthropic
from PIL import Image, ImageOps

# ----------------------------------------------------------------------------
# Configuration (override the models/sizes here if needed)
# ----------------------------------------------------------------------------
TRIAGE_MODEL = "claude-haiku-4-5"   # Stage 1: cheap/fast, every image
HERO_MODEL = "claude-opus-4-5"      # Stage 2: full quality, top-N only

TRIAGE_LONG_EDGE = 768              # downscale long edge for the coarse pass
HERO_LONG_EDGE = 1568              # downscale long edge for the quality pass
JPEG_QUALITY = 85

DEFAULT_TOP_N = 12
DEFAULT_WORKERS = 5
MAX_IMAGES_PER_REQUEST = 100        # Anthropic hard cap on images in one call

TRIAGE_MAX_TOKENS = 200
HERO_MAX_TOKENS = 8000             # report fits well under non-streaming timeout

# Retry/backoff (we own backoff; the SDK client is created with max_retries=0)
MAX_RETRIES = 6
BASE_DELAY = 1.0
MAX_DELAY = 60.0
RETRY_STATUS = {408, 409, 429}     # plus anything >= 500

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
REPORT_NAME = "hero_report.md"
HTML_REPORT_NAME = "hero_report.html"
CSV_NAME = "triage_scores.csv"
OUTPUT_NAMES = {REPORT_NAME, HTML_REPORT_NAME, CSV_NAME}

SKILL_FILENAME = "SKILL.md"

# ────────────────────────────────────────────────────────────────────────────
# TTY-aware color helpers
# Respects NO_COLOR (https://no-color.org) and non-TTY pipes automatically.
# ────────────────────────────────────────────────────────────────────────────
def _use_color():
    return sys.stdout.isatty() and not os.environ.get("NO_COLOR")

def _c(code, text):
    return (code + text + "\033[0m") if _use_color() else text

_BOLD   = "\033[1m"
_DIM    = "\033[2m"
_GREEN  = "\033[32m"
_YELLOW = "\033[33m"
_CYAN   = "\033[36m"


def _fmt_score(score):
    s = "%2d/60" % score
    if score >= 45:
        return _c(_GREEN + _BOLD, s)
    if score >= 30:
        return _c(_YELLOW, s)
    return _c(_DIM, s)


def _fmt_tag(is_exterior):
    return _c(_CYAN, "EXT") if is_exterior else _c(_DIM, "int")


# Pillow resample constant moved namespaces across versions
try:
    _RESAMPLE = Image.Resampling.LANCZOS
except AttributeError:  # Pillow < 9.1
    _RESAMPLE = Image.LANCZOS

# Toggled off (process-wide) the first time structured outputs are rejected,
# so we don't keep paying for 400s on an SDK/model that doesn't support them.
_USE_STRUCTURED = [True]

TRIAGE_SYSTEM = (
    "You score ONE real-estate photo for West Coast Modern hero-image fit "
    "(luxury architectural real estate). Rate 0-60 overall on: architecture "
    "clarity, natural directional light, West Coast materiality (wood, concrete, "
    "glass, stone, natural landscaping), breathing room, emotional pull, clean "
    "foreground, horizontal preferred. Exteriors score higher than interiors. "
    'Return ONLY minified JSON: {"score":<int 0-60>,"isExterior":<true|false>,'
    '"note":"<max 5 words>"}'
)

TRIAGE_SCHEMA = {
    "type": "object",
    "properties": {
        "score": {"type": "integer"},
        "isExterior": {"type": "boolean"},
        "note": {"type": "string"},
    },
    "required": ["score", "isExterior", "note"],
    "additionalProperties": False,
}


# ----------------------------------------------------------------------------
# Auth / client
# ----------------------------------------------------------------------------
def make_client():
    """Build an Anthropic client from ANTHROPIC_API_KEY. Fail clearly if unset.

    max_retries=0 — we implement our own exponential backoff in _messages_create.
    """
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        sys.stderr.write(
            "ERROR: ANTHROPIC_API_KEY is not set.\n"
            "Set it before running, e.g.:\n"
            '    export ANTHROPIC_API_KEY="sk-ant-..."\n'
            "Run 'wcm doctor' to check all prerequisites.\n"
        )
        raise SystemExit(78)  # EX_CONFIG — configuration error
    return anthropic.Anthropic(api_key=key, max_retries=0)


# ----------------------------------------------------------------------------
# Image discovery + encoding
# ----------------------------------------------------------------------------
def find_images(folder):
    """Return sorted image files directly in *folder* (skips hidden + outputs)."""
    out = []
    for p in sorted(Path(folder).iterdir()):
        if not p.is_file() or p.name.startswith("."):
            continue
        if p.name in OUTPUT_NAMES:
            continue
        if p.suffix.lower() in IMAGE_EXTS:
            out.append(p)
    return out


def encode_image(path, long_edge):
    """Downscale to *long_edge* on the long side and return base64 JPEG bytes."""
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im)  # honor camera rotation
        if im.mode != "RGB":
            im = im.convert("RGB")         # flatten P/RGBA/L/animated-first-frame
        im.thumbnail((long_edge, long_edge), _RESAMPLE)
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=JPEG_QUALITY)
    return base64.standard_b64encode(buf.getvalue()).decode("ascii")


def _image_block(b64):
    return {
        "type": "image",
        "source": {"type": "base64", "media_type": "image/jpeg", "data": b64},
    }


# ----------------------------------------------------------------------------
# Low-level API call with exponential backoff (single layer)
# ----------------------------------------------------------------------------
def _messages_create(client, **kwargs):
    last = None
    delay = BASE_DELAY
    for attempt in range(MAX_RETRIES + 1):
        try:
            return client.messages.create(**kwargs)
        except anthropic.APIConnectionError as e:  # incl. timeouts
            last = e
        except anthropic.APIStatusError as e:
            status = getattr(e, "status_code", 0)
            if status not in RETRY_STATUS and status < 500:
                raise  # 4xx (bad request, auth, etc.) — not retryable
            last = e
        if attempt < MAX_RETRIES:
            time.sleep(min(delay + random.uniform(0, 0.5), MAX_DELAY))
            delay *= 2
    raise last  # exhausted retries


def _text_of(resp):
    parts = [b.text for b in resp.content if getattr(b, "type", None) == "text"]
    return "".join(parts).strip()


# ----------------------------------------------------------------------------
# Stage 1 — triage
# ----------------------------------------------------------------------------
def _triage_create(client, b64, structured):
    content = [_image_block(b64), {"type": "text", "text": "Score this image."}]
    kwargs = dict(
        model=TRIAGE_MODEL,
        max_tokens=TRIAGE_MAX_TOKENS,
        system=TRIAGE_SYSTEM,
        messages=[{"role": "user", "content": content}],
    )
    if structured:
        kwargs["output_config"] = {
            "format": {"type": "json_schema", "schema": TRIAGE_SCHEMA}
        }
    return _messages_create(client, **kwargs)


def _parse_triage_json(text):
    """Parse the triage JSON; tolerate stray prose around it. None on failure."""
    if not text:
        return None
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        pass
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except (ValueError, TypeError):
        return None


def _result(name, score, is_exterior, note):
    return {"file": name, "score": score, "isExterior": is_exterior, "note": note}


def triage_one(client, path):
    """Score a single image. Never raises — returns score 0 on any failure."""
    name = path.name
    try:
        b64 = encode_image(path, TRIAGE_LONG_EDGE)
    except Exception as e:  # unreadable/corrupt file
        return _result(name, 0, False, "encode error: %s" % type(e).__name__)

    try:
        if _USE_STRUCTURED[0]:
            try:
                resp = _triage_create(client, b64, structured=True)
            except (TypeError, anthropic.BadRequestError):
                # SDK/model rejected output_config — stop trying it process-wide.
                _USE_STRUCTURED[0] = False
                resp = _triage_create(client, b64, structured=False)
        else:
            resp = _triage_create(client, b64, structured=False)
    except Exception as e:
        return _result(name, 0, False, "api error: %s" % type(e).__name__)

    parsed = _parse_triage_json(_text_of(resp))
    if not isinstance(parsed, dict):
        return _result(name, 0, False, "bad json")

    try:
        score = int(round(float(parsed.get("score", 0))))
    except (ValueError, TypeError):
        score = 0
    score = max(0, min(60, score))
    is_exterior = bool(parsed.get("isExterior", False))
    note = str(parsed.get("note", "")).strip().replace("\n", " ")[:60]
    return _result(name, score, is_exterior, note)


def run_triage(client, paths, workers):
    """Triage every path in parallel; print per-image progress. Preserves order."""
    n = len(paths)
    print("Stage 1 — triaging %d image(s) with %d worker(s)..." % (n, workers))
    results = [None] * n
    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        fut_to_idx = {ex.submit(triage_one, client, p): i for i, p in enumerate(paths)}
        done = 0
        for fut in as_completed(fut_to_idx):
            i = fut_to_idx[fut]
            r = fut.result()
            results[i] = r
            done += 1
            print("  [%d/%d] %-40s %s %s  %s"
                  % (done, n, r["file"][:40],
                     _fmt_score(r["score"]), _fmt_tag(r["isExterior"]), r["note"]))
    return [r for r in results if r is not None]


# ----------------------------------------------------------------------------
# Stage 2 — hero pick
# ----------------------------------------------------------------------------
def load_skill(skill_path=None):
    if skill_path:
        p = Path(skill_path)
    else:
        p = Path(__file__).resolve().parent / SKILL_FILENAME
    if not p.is_file():
        raise SystemExit("ERROR: SKILL.md not found at %s" % p)
    return p.read_text(encoding="utf-8")


def stage2_hero(client, folder, top_results, total_count, skill_text, property_name):
    folder = Path(folder)
    n = len(top_results)
    framing = (
        "Property: %s\n"
        "Total images in shoot: %d\n"
        "Hero candidates below: %d highest-scoring shots from the Stage-1 triage "
        "(already pre-filtered — these are NOT the full set).\n"
        "Date: %s\n\n"
        "Each image is labeled with its filename and triage metadata "
        "(score out of 60, Exterior/Interior). Produce the full Hero Image "
        "Selection Report in the exact format from your instructions, using ONLY "
        "the filenames shown below.\n\n"
        "Because you only see the top %d candidates (not the whole shoot), scope "
        "the Suggested Tour Sequence and Cuts to these images only — never invent "
        "filenames. If the set appears to be missing a category the hero workflow "
        "needs (e.g. no exterior, no entry, no great room), say so in "
        "FLAGS / NOTES FOR TRENT rather than fabricating one."
        % (property_name, total_count, n, date.today().isoformat(), n)
    )

    content = [{"type": "text", "text": framing}]
    used = 0
    for r in top_results:
        p = folder / r["file"]
        try:
            b64 = encode_image(p, HERO_LONG_EDGE)
        except Exception:
            continue  # unencodable at full size — drop from the Stage-2 set
        label = "Image: %s — triage %d/60, %s%s" % (
            r["file"], r["score"],
            "Exterior" if r["isExterior"] else "Interior",
            (", note: %s" % r["note"]) if r["note"] else "",
        )
        content.append({"type": "text", "text": label})
        content.append(_image_block(b64))
        used += 1

    if used == 0:
        raise SystemExit("ERROR: none of the top candidates could be encoded.")

    content.append({
        "type": "text",
        "text": "Produce the full Hero Image Selection Report now, in the exact "
                "format specified, using only the filenames listed above.",
    })

    resp = _messages_create(
        client,
        model=HERO_MODEL,
        max_tokens=HERO_MAX_TOKENS,
        system=skill_text,
        messages=[{"role": "user", "content": content}],
    )
    return _text_of(resp)


# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------
def write_csv(folder, results):
    path = Path(folder) / CSV_NAME
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["file", "score", "isExterior", "note"])
        for r in results:
            w.writerow([r["file"], r["score"], r["isExterior"], r["note"]])
    return path


def load_csv(path):
    """Read triage results back from a previously written CSV. Returns list of result dicts."""
    results = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                score = int(row["score"])
            except (KeyError, ValueError):
                score = 0
            results.append({
                "file": row["file"],
                "score": max(0, min(60, score)),
                "isExterior": row.get("isExterior", "False") == "True",
                "note": row.get("note", ""),
            })
    return results


# ----------------------------------------------------------------------------
# HTML report
# ----------------------------------------------------------------------------
def _h(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def _inline_md(text):
    return re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)


def _score_color_css(score):
    if score >= 45:
        return "#7db87d"
    if score >= 30:
        return "#c4956a"
    return "#777"


def _report_lines_to_html(text):
    lines = text.split("\n")
    out = []
    in_ol = False

    def close_list():
        nonlocal in_ol
        if in_ol:
            out.append("</ol>")
            in_ol = False

    for raw in lines:
        s = raw.strip()

        # ━ or ─ separator lines
        if s and all(c in "━─" for c in s):
            close_list()
            out.append('<div class="sep"></div>')
            continue

        if not s:
            close_list()
            continue

        # Score: 54/60
        m = re.match(r"Score:\s*(\d+)/(\d+)", s)
        if m:
            score, total = int(m.group(1)), int(m.group(2))
            close_list()
            out.append(
                '<div class="score-display">'
                '<span class="score-num" style="color:%s">%d</span>'
                '<span class="score-denom">/%d</span>'
                '</div>' % (_score_color_css(score), score, total)
            )
            continue

        # Breakdown: Architecture 9 | Light 9 | ...
        if s.startswith("Breakdown:"):
            parts = s[10:].strip().split("|")
            dims = []
            for p in parts:
                p = p.strip()
                dm = re.match(r"(.+?)\s+(\d+)$", p)
                if dm:
                    lbl, val = dm.group(1), int(dm.group(2))
                    dims.append(
                        '<div class="dim">'
                        '<span class="dim-lbl">%s</span>'
                        '<div class="dim-bar"><div class="dim-fill" style="width:%.0f%%"></div></div>'
                        '<span class="dim-val">%s</span>'
                        '</div>' % (_h(lbl), val / 10 * 100, _h(str(val)))
                    )
                else:
                    dims.append('<div class="dim">%s</div>' % _h(p))
            close_list()
            out.append('<div class="breakdown">%s</div>' % "".join(dims))
            continue

        # Image: filename
        if s.startswith("Image:"):
            fname = s[6:].strip()
            close_list()
            out.append(
                '<div class="image-ref">%s</div>'
                '<img class="candidate-img" src="%s" alt="%s" loading="lazy">'
                % (_h(fname), _h(fname), _h(fname))
            )
            continue

        # Use for: ...
        if s.startswith("Use for:"):
            close_list()
            out.append('<p class="use-for"><em>Use for:</em> %s</p>' % _h(s[8:].strip()))
            continue

        # ⚠ flag lines
        if s.startswith("⚠"):
            close_list()
            out.append('<div class="flag-item">%s</div>' % _inline_md(_h(s)))
            continue

        # Numbered list
        m = re.match(r"^(\d+)\.\s+(.+)$", s)
        if m:
            if not in_ol:
                out.append('<ol class="report-list">')
                in_ol = True
            out.append('<li>%s</li>' % _inline_md(_h(m.group(2))))
            continue

        # Section heading heuristic: mostly uppercase letters, short line
        alpha = [c for c in s if c.isalpha()]
        if alpha and len(s) < 100 and sum(c.isupper() for c in alpha) / len(alpha) > 0.7:
            close_list()
            out.append('<h2 class="section-head">%s</h2>' % _h(s))
            continue

        # Regular paragraph
        close_list()
        out.append('<p class="body-text">%s</p>' % _inline_md(_h(s)))

    close_list()
    return "\n".join(out)


def _triage_table_html(all_results):
    rows = []
    for r in sorted(all_results, key=lambda x: (-x["score"], x["file"].lower())):
        score = r["score"]
        ext_class = "ext" if r["isExterior"] else "int"
        ext_label = "Exterior" if r["isExterior"] else "Interior"
        rows.append(
            '<tr>'
            '<td class="file-col">%s</td>'
            '<td class="score-col" style="color:%s">%d/60</td>'
            '<td class="%s">%s</td>'
            '<td class="note-col">%s</td>'
            '</tr>' % (
                _h(r["file"]), _score_color_css(score), score,
                ext_class, _h(ext_label), _h(r.get("note", ""))
            )
        )
    return (
        '<table class="triage-table"><thead><tr>'
        '<th>File</th><th>Score</th><th>Type</th><th>Note</th>'
        '</tr></thead><tbody>%s</tbody></table>' % "\n".join(rows)
    )


_HTML_CSS = """
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}

:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.145 0 0);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.145 0 0);
  --primary: oklch(0.508 0.118 165.612);
  --primary-foreground: oklch(0.979 0.021 166.113);
  --secondary: oklch(0.967 0.001 286.375);
  --secondary-foreground: oklch(0.21 0.006 285.885);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --destructive: oklch(0.577 0.245 27.325);
  --border: oklch(0.922 0 0);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
  --chart-1: oklch(0.87 0 0);
  --chart-2: oklch(0.556 0 0);
  --chart-3: oklch(0.439 0 0);
  --chart-4: oklch(0.371 0 0);
  --chart-5: oklch(0.269 0 0);
  --radius: 0;
  --sidebar: oklch(0.985 0 0);
  --sidebar-foreground: oklch(0.145 0 0);
  --sidebar-primary: oklch(0.596 0.145 163.225);
  --sidebar-primary-foreground: oklch(0.979 0.021 166.113);
  --sidebar-accent: oklch(0.97 0 0);
  --sidebar-accent-foreground: oklch(0.205 0 0);
  --sidebar-border: oklch(0.922 0 0);
  --sidebar-ring: oklch(0.708 0 0);
  /* WCM additions */
  --score-high: oklch(0.65 0.15 145);
  --score-mid: var(--primary);
  --score-low: var(--muted-foreground);
  --serif: 'Palatino Linotype','Book Antiqua',Palatino,Georgia,serif;
  --mono: 'SF Mono','Fira Code',monospace;
}

.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --card: oklch(0.205 0 0);
  --card-foreground: oklch(0.985 0 0);
  --popover: oklch(0.205 0 0);
  --popover-foreground: oklch(0.985 0 0);
  --primary: oklch(0.432 0.095 166.913);
  --primary-foreground: oklch(0.979 0.021 166.113);
  --secondary: oklch(0.274 0.006 286.033);
  --secondary-foreground: oklch(0.985 0 0);
  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --accent: oklch(0.269 0 0);
  --accent-foreground: oklch(0.985 0 0);
  --destructive: oklch(0.704 0.191 22.216);
  --border: oklch(1 0 0 / 10%);
  --input: oklch(1 0 0 / 15%);
  --ring: oklch(0.556 0 0);
  --chart-1: oklch(0.87 0 0);
  --chart-2: oklch(0.556 0 0);
  --chart-3: oklch(0.439 0 0);
  --chart-4: oklch(0.371 0 0);
  --chart-5: oklch(0.269 0 0);
  --sidebar: oklch(0.205 0 0);
  --sidebar-foreground: oklch(0.985 0 0);
  --sidebar-primary: oklch(0.696 0.17 162.48);
  --sidebar-primary-foreground: oklch(0.262 0.051 172.552);
  --sidebar-accent: oklch(0.269 0 0);
  --sidebar-accent-foreground: oklch(0.985 0 0);
  --sidebar-border: oklch(1 0 0 / 10%);
  --sidebar-ring: oklch(0.556 0 0);
  /* WCM additions */
  --score-high: oklch(0.65 0.15 145);
  --score-mid: var(--primary);
  --score-low: var(--muted-foreground);
}

body{background:var(--background);color:var(--foreground);
  font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Arial,sans-serif;
  font-size:15px;line-height:1.7}
.masthead{background:var(--card);border-bottom:1px solid var(--border);padding:48px 64px 36px}
.wordmark{font-size:10px;letter-spacing:.28em;text-transform:uppercase;
  color:var(--primary);margin-bottom:18px}
.masthead h1{font-family:var(--serif);font-size:34px;font-weight:normal;
  letter-spacing:-.01em;line-height:1.2;margin-bottom:10px}
.masthead-meta{font-size:11px;letter-spacing:.1em;text-transform:uppercase;
  color:var(--muted-foreground)}
.masthead-meta span{margin-right:24px}
.report-body{max-width:860px;margin:0 auto;padding:48px 64px}
.sep{border-top:1px solid var(--border);margin:28px 0}
h2.section-head{font-size:10px;font-weight:600;letter-spacing:.22em;
  text-transform:uppercase;color:var(--primary);margin:36px 0 12px}
.score-display{margin:8px 0 12px}
.score-num{font-family:var(--serif);font-size:50px;font-weight:normal;line-height:1}
.score-denom{font-family:var(--serif);font-size:20px;color:var(--muted-foreground)}
.breakdown{display:flex;flex-wrap:wrap;gap:10px 20px;margin:12px 0 20px;
  padding:16px 20px;background:var(--card);border:1px solid var(--border)}
.dim{display:flex;align-items:center;gap:8px;font-size:12px;min-width:170px}
.dim-lbl{color:var(--muted-foreground);width:120px;flex-shrink:0}
.dim-bar{flex:1;height:3px;background:var(--border);min-width:60px}
.dim-fill{height:100%;background:var(--primary)}
.dim-val{color:var(--foreground);width:14px;text-align:right}
.image-ref{font-family:var(--mono);font-size:13px;color:var(--primary);
  background:var(--card);display:inline-block;padding:4px 10px;
  border:1px solid var(--border);margin:4px 0 0}
.candidate-img{display:block;width:100%;max-height:520px;object-fit:cover;
  object-position:center;margin:12px 0 20px;border:1px solid var(--border)}
.use-for{font-size:13px;color:var(--muted-foreground);margin:8px 0 16px}
.use-for em{font-style:normal;color:var(--foreground)}
.body-text{color:var(--foreground);margin:10px 0;max-width:680px}
.report-list{margin:10px 0 10px 20px}
.report-list li{margin:6px 0}
.flag-item{margin:12px 0;padding:12px 16px;border-left:2px solid var(--primary);
  background:color-mix(in oklch,var(--primary) 8%,transparent);
  font-size:14px;max-width:680px}
.triage-section{margin-top:64px;padding-top:40px;border-top:1px solid var(--border)}
.triage-heading{font-size:10px;font-weight:600;letter-spacing:.22em;
  text-transform:uppercase;color:var(--primary);margin-bottom:20px}
.triage-table{width:100%;border-collapse:collapse;font-size:13px}
.triage-table th{text-align:left;padding:8px 12px;font-size:10px;font-weight:600;
  letter-spacing:.12em;text-transform:uppercase;color:var(--muted-foreground);
  border-bottom:1px solid var(--border)}
.triage-table td{padding:9px 12px;border-bottom:1px solid var(--border);vertical-align:middle}
.triage-table tbody tr:hover td{background:var(--muted)}
.file-col{font-family:var(--mono);font-size:12px}
.score-col{font-weight:600}
.ext{color:var(--score-high);font-size:11px;letter-spacing:.05em}
.int{color:var(--muted-foreground);font-size:11px;letter-spacing:.05em}
.note-col{color:var(--muted-foreground);font-size:12px}
.report-footer{margin-top:80px;padding-top:20px;border-top:1px solid var(--border);
  font-size:11px;letter-spacing:.08em;text-transform:uppercase;
  color:var(--muted-foreground);opacity:0.4}
"""

_HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en" class="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Hero Report — {property_name}</title>
<style>{css}
.theme-toggle{{position:fixed;top:20px;right:24px;z-index:100;
  background:var(--card);border:1px solid var(--border);color:var(--muted-foreground);
  font-size:11px;letter-spacing:.12em;text-transform:uppercase;
  padding:6px 14px;cursor:pointer;transition:color .15s,border-color .15s}}
.theme-toggle:hover{{color:var(--foreground);border-color:var(--ring)}}
</style>
</head>
<body>
<button class="theme-toggle" id="themeBtn" onclick="toggleTheme()">Light</button>
<header class="masthead">
  <div class="wordmark">West Coast Modern</div>
  <h1>Hero Image Report</h1>
  <div class="masthead-meta">
    <span>{property_name}</span>
    <span>{report_date}</span>
    <span>{image_count} images reviewed</span>
  </div>
</header>
<main class="report-body">
{report_html}
<section class="triage-section">
  <div class="triage-heading">Stage 1 — Full Triage Scores</div>
  {triage_html}
</section>
<footer class="report-footer">West Coast Modern — Architecture, not real estate.</footer>
</main>
<script>
(function(){{
  var saved=localStorage.getItem('wcm-theme');
  if(saved==='light'){{document.documentElement.classList.remove('dark');document.getElementById('themeBtn').textContent='Dark';}}
}})();
function toggleTheme(){{
  var html=document.documentElement,btn=document.getElementById('themeBtn');
  if(html.classList.contains('dark')){{html.classList.remove('dark');btn.textContent='Dark';localStorage.setItem('wcm-theme','light');}}
  else{{html.classList.add('dark');btn.textContent='Light';localStorage.setItem('wcm-theme','dark');}}
}}
</script>
</body>
</html>"""


def build_html_report(property_name, report_date, report_text, all_results):
    return _HTML_TEMPLATE.format(
        property_name=_h(property_name),
        report_date=_h(report_date),
        image_count=len(all_results),
        css=_HTML_CSS,
        report_html=_report_lines_to_html(report_text),
        triage_html=_triage_table_html(all_results),
    )


def write_html_report(folder, property_name, report_date, report_text, all_results):
    path = Path(folder) / HTML_REPORT_NAME
    path.write_text(
        build_html_report(property_name, report_date, report_text, all_results),
        encoding="utf-8",
    )
    return path


# ----------------------------------------------------------------------------
# End-of-run summary
# ----------------------------------------------------------------------------
def _print_summary(all_results, top_results, report_path, html_path, elapsed):
    """Print a structured completion summary with next-action hint."""
    mins, secs = divmod(int(elapsed), 60)
    elapsed_str = ("%dm %ds" % (mins, secs)) if mins else ("%ds" % secs)
    sep = _c(_DIM, "─" * 60)

    print("\n" + sep)
    print(_c(_BOLD, "  Hero Selection Complete"))
    print(sep)
    print("  Images triaged  : " + _c(_BOLD, str(len(all_results))))
    print("  Elapsed         : " + elapsed_str)
    print()
    print("  " + _c(_BOLD, "Top picks:"))
    for i, r in enumerate(top_results[:3], 1):
        print("  %d. %-38s %s %s" % (
            i, r["file"][:38],
            _fmt_score(r["score"]),
            _fmt_tag(r["isExterior"]),
        ))
    print()
    print("  Report (md)     → " + _c(_CYAN, str(report_path)))
    print("  Report (html)   → " + _c(_CYAN, str(html_path)))
    print("  Next            → open '%s'" % html_path)
    print(sep)


# ----------------------------------------------------------------------------
# Orchestration
# ----------------------------------------------------------------------------
def process_folder(client, folder, top_n=DEFAULT_TOP_N, workers=DEFAULT_WORKERS,
                   skill_path=None, images=None, skip_if_done=False, resume=False):
    """Run the full two-stage pipeline on *folder*. Returns the report path or None.

    resume=True: if triage_scores.csv already exists, reload Stage 1 from it and
    skip directly to Stage 2. Useful when Stage 1 finished but Stage 2 failed.
    """
    t0 = time.time()
    folder = Path(folder)
    report_path = folder / REPORT_NAME
    existing_csv = folder / CSV_NAME

    if skip_if_done and report_path.exists():
        print("[skip] %s already has %s" % (folder, REPORT_NAME))
        return None

    if images is None:
        images = find_images(folder)
    if not images and not (resume and existing_csv.exists()):
        sys.stderr.write("No images found in %s — nothing to do.\n" % folder)
        return None

    if top_n > MAX_IMAGES_PER_REQUEST:
        sys.stderr.write("WARNING: --top %d exceeds the %d-image/request cap; "
                         "clamping to %d.\n"
                         % (top_n, MAX_IMAGES_PER_REQUEST, MAX_IMAGES_PER_REQUEST))
        top_n = MAX_IMAGES_PER_REQUEST

    skill_text = load_skill(skill_path)
    property_name = folder.name or "Untitled"

    if resume and existing_csv.exists():
        print("--resume: loading Stage 1 scores from %s (skipping triage)." % existing_csv)
        results = load_csv(existing_csv)
        if not results:
            sys.stderr.write("WARNING: %s is empty — falling back to full triage.\n"
                             % existing_csv)
            results = run_triage(client, images, workers)
    else:
        if resume:
            print("--resume: no existing %s found — running full triage." % CSV_NAME)
        if not images:
            sys.stderr.write("No images found in %s — nothing to do.\n" % folder)
            return None
        results = run_triage(client, images, workers)

    results.sort(key=lambda r: (-r["score"], r["file"].lower()))
    if not (resume and existing_csv.exists() and results):
        csv_path = write_csv(folder, results)
        print("Wrote %s" % csv_path)

    top = results[:top_n]
    print("\nTop %d candidates:" % len(top))
    for rank, r in enumerate(top, 1):
        print("  %2d. %-40s %s %s"
              % (rank, r["file"][:40],
                 _fmt_score(r["score"]), _fmt_tag(r["isExterior"])))

    print("\nStage 2 — hero pick with %s (%d image(s))..." % (HERO_MODEL, len(top)))
    report = stage2_hero(client, folder, top, len(results), skill_text, property_name)
    report_path.write_text(report, encoding="utf-8")
    print("Wrote %s" % report_path)
    html_path = write_html_report(
        folder, property_name, date.today().isoformat(), report, results
    )
    print("Wrote %s" % html_path)
    _print_summary(results, top, report_path, html_path, time.time() - t0)
    return report_path


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Two-stage WCM hero-image selection.")
    ap.add_argument("folder", help="Path to the property photo folder")
    ap.add_argument("--top", type=int, default=DEFAULT_TOP_N,
                    help="How many top images go to Stage 2 (default %d)" % DEFAULT_TOP_N)
    ap.add_argument("--workers", type=int, default=DEFAULT_WORKERS,
                    help="Parallel triage workers (default %d)" % DEFAULT_WORKERS)
    ap.add_argument("--skill", default=None,
                    help="Path to SKILL.md (default: next to this script)")
    ap.add_argument("--resume", action="store_true",
                    help="Skip Stage 1 and reload triage scores from an existing "
                         "%s (useful when Stage 1 finished but Stage 2 failed)" % CSV_NAME)
    args = ap.parse_args(argv)

    try:  # live progress even when stdout is piped (e.g. launchd logs)
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    folder = Path(args.folder)
    if not folder.is_dir():
        sys.stderr.write("ERROR: not a directory: %s\n" % folder)
        return 1

    # Discovery first (no API key needed) so it's visible before the auth check.
    images = find_images(folder)
    print("Found %d image(s) in %s" % (len(images), folder))
    if not images:
        sys.stderr.write("ERROR: no supported images (%s) in %s\n"
                         % (", ".join(sorted(IMAGE_EXTS)), folder))
        return 1

    client = make_client()  # fails clearly if ANTHROPIC_API_KEY is missing
    process_folder(client, folder, top_n=args.top, workers=args.workers,
                   skill_path=args.skill, images=images, resume=args.resume)
    return 0


if __name__ == "__main__":
    sys.exit(main())
