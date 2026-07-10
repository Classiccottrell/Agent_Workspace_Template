"""Brand + terminal-style tokens, shared by the whole hero-image CLI.

This is the single seam for white-labelling. Rebrand by editing the four
tokens below, or override them per-run via environment variables:

    HERO_BRAND_NAME     e.g. "Harbour & Fog Studio"
    HERO_BRAND_SHORT    the CLI verb / prog name, e.g. "hfs"
    HERO_BRAND_TAGLINE  footer / banner line
    HERO_BRAND_ACCENT   accent colour as #rrggbb

Every visual surface (banner, accent colour, summary chrome) reads from here,
so a rebrand is a one-file change. Colour output degrades automatically on
non-TTY streams (pipes, the launchd `watch` log) and when NO_COLOR is set.
"""
from __future__ import annotations

import os
import sys

NAME    = os.environ.get("HERO_BRAND_NAME", "West Coast Modern")
SHORT   = os.environ.get("HERO_BRAND_SHORT", "wcm")
TAGLINE = os.environ.get("HERO_BRAND_TAGLINE", "Architecture, not real estate.")
ACCENT_HEX = os.environ.get("HERO_BRAND_ACCENT", "#3a7ca5")

# ---------------------------------------------------------------------------
# TTY-aware colour. Respects NO_COLOR (https://no-color.org) and non-TTY
# pipes/daemon logs automatically — the one gate every visual must pass.
# ---------------------------------------------------------------------------
def _use_color():
    return sys.stdout.isatty() and not os.environ.get("NO_COLOR")

def _c(code, text):
    return (code + text + "\033[0m") if _use_color() else text

_BOLD   = "\033[1m"
_DIM    = "\033[2m"
_GREEN  = "\033[32m"
_YELLOW = "\033[33m"
_RED    = "\033[31m"
_CYAN   = "\033[36m"


def _accent_code():
    h = ACCENT_HEX.lstrip("#")
    try:
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return "\033[38;2;%d;%d;%dm" % (r, g, b)
    except (ValueError, IndexError):
        return _CYAN  # ponytail: bad hex → fall back to the 16-colour accent

_ACCENT = _accent_code()


def accent(text):
    return _c(_ACCENT, text)


def rule(width=60):
    return _c(_DIM, "─" * width)


def banner(subtitle=""):
    """Brand header. Accented wordmark on a TTY; plain one-liner in logs/pipes."""
    if not _use_color():
        return ("%s — %s" % (NAME, subtitle)) if subtitle else NAME
    head = _c(_ACCENT + _BOLD, NAME) + "   " + _c(_DIM, TAGLINE)
    body = ("\n  " + _c(_BOLD, subtitle)) if subtitle else ""
    return "\n  " + head + body + "\n  " + rule()


if __name__ == "__main__":  # ponytail: eyeball both render paths
    print(banner("doctor — pre-flight checks"))
    print(accent("accent sample") + "  " + _c(_GREEN, "ok") + "  " + _c(_RED, "fail"))
    assert banner("x") and rule() and accent("y")  # non-empty in TTY-off test env
    print("\nself-check ok")
