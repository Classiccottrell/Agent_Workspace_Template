#!/usr/bin/env python3
"""wcm — West Coast Modern hero-image pipeline CLI.

Subcommands:
  doctor  Pre-flight check: API key, SKILL.md, Python version, dependencies.
  run     Run the two-stage pipeline on a single property folder.
  watch   Watch a parent directory and auto-process new property subfolders.

Install:
    pip install -e Hero-Image-Agent/
    export ANTHROPIC_API_KEY="sk-ant-..."

Usage:
    wcm doctor
    wcm run /path/to/PropertyName [--top 12] [--workers 5] [--resume]
    wcm watch /path/to/Parent [--top 12] [--workers 5] [--scan-existing]
"""
from __future__ import annotations

import argparse
import importlib
import os
import sys
import threading
import time
from pathlib import Path

import hero_select as hs


# ---------------------------------------------------------------------------
# TTY-aware color helpers (mirrors hero_select.py; respects NO_COLOR)
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


# ---------------------------------------------------------------------------
# doctor
# ---------------------------------------------------------------------------

def cmd_doctor(args):
    """Pre-flight check: Python, dependencies, API key, SKILL.md, API auth."""
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    all_ok = True

    def check(label, passed, fix=None):
        nonlocal all_ok
        if passed:
            print(_c(_GREEN, "  ✓") + "  " + label)
        else:
            all_ok = False
            print(_c(_RED,   "  ✗") + "  " + label)
            if fix:
                print("       fix: " + _c(_YELLOW, fix))

    print(_c(_BOLD, "\nwcm doctor — pre-flight checks\n"))

    # 1. Python version
    v = sys.version_info
    check(
        "Python %d.%d.%d (need ≥ 3.9)" % (v.major, v.minor, v.micro),
        (v.major, v.minor) >= (3, 9),
        fix="Download Python 3.9+ from https://python.org/downloads",
    )

    # 2. Dependencies
    for pkg, mod in [("anthropic", "anthropic"), ("Pillow", "PIL"), ("watchdog", "watchdog")]:
        try:
            importlib.import_module(mod)
            check("%s installed" % pkg, True)
        except ImportError:
            check("%s installed" % pkg, False, fix="pip install %s" % pkg)

    # 3. API key present
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    check(
        "ANTHROPIC_API_KEY is set",
        bool(key),
        fix='export ANTHROPIC_API_KEY="sk-ant-..."',
    )

    # 4. API key authenticates (only if set and anthropic is importable)
    if key:
        try:
            import anthropic as _ant
            client = _ant.Anthropic(api_key=key, max_retries=0)
            client.models.list()
            check("API key authenticates with Anthropic", True)
        except Exception as e:
            check(
                "API key authenticates with Anthropic",
                False,
                fix="Check your key at https://console.anthropic.com — %s" % type(e).__name__,
            )

    # 5. SKILL.md present
    script_dir = Path(hs.__file__).resolve().parent
    skill_md = script_dir / hs.SKILL_FILENAME
    check(
        "SKILL.md found at %s" % skill_md,
        skill_md.is_file(),
        fix="Ensure SKILL.md exists in %s" % script_dir,
    )

    print()
    if all_ok:
        print(_c(_GREEN, "  All checks passed.") + " Ready to run wcm.")
        print("  Next: " + _c(_CYAN, "wcm run /path/to/PropertyName"))
    else:
        print(_c(_RED, "  One or more checks failed.") + " Fix the issues above, then re-run:")
        print("       " + _c(_CYAN, "wcm doctor"))
    print()

    return 0 if all_ok else 78  # 78 = EX_CONFIG (sysexits.h)


# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------

def cmd_run(args):
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    folder = Path(args.folder)
    if not folder.is_dir():
        sys.stderr.write(
            "ERROR: not a directory: %s\n"
            "       fix: check the path, or run 'wcm doctor'\n" % folder
        )
        return 3  # EX_NOINPUT — resource not found

    images = hs.find_images(folder)
    print("Found %d image(s) in %s" % (len(images), folder))

    if not images and not args.resume:
        sys.stderr.write(
            "ERROR: no supported images (%s) in %s\n"
            "       fix: check the folder contents, or use --resume if triage already ran\n"
            % (", ".join(sorted(hs.IMAGE_EXTS)), folder)
        )
        return 3

    if not images and args.resume:
        existing_csv = folder / hs.CSV_NAME
        if not existing_csv.exists():
            sys.stderr.write(
                "ERROR: --resume requested but no %s found in %s and no images to triage.\n"
                "       fix: remove --resume to run a full triage, or add images to the folder\n"
                % (hs.CSV_NAME, folder)
            )
            return 3

    client = hs.make_client()
    try:
        hs.process_folder(
            client, folder,
            top_n=args.top,
            workers=args.workers,
            skill_path=args.skill,
            images=images if images else None,
            resume=args.resume,
        )
    except Exception as e:
        sys.stderr.write("ERROR: %s\n       run 'wcm doctor' to check prerequisites\n" % e)
        return 1
    return 0


# ---------------------------------------------------------------------------
# watch
# ---------------------------------------------------------------------------

def cmd_watch(args):
    from watch_folder import FolderTracker, _Handler
    from watchdog.observers import Observer

    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    parent = Path(args.parent)
    if not parent.is_dir():
        sys.stderr.write(
            "ERROR: not a directory: %s\n"
            "       fix: check the path\n" % parent
        )
        return 3

    client = hs.make_client()

    tracker = FolderTracker(parent, client, args.top, args.workers, args.skill)
    if args.scan_existing:
        tracker.seed_existing()

    observer = Observer()
    observer.schedule(_Handler(tracker), str(parent.resolve()), recursive=True)
    observer.start()

    monitor = threading.Thread(target=tracker.monitor_loop, daemon=True)
    monitor.start()

    print(
        "[watch] watching %s (stable=30s, top=%d, workers=%d). Ctrl-C to stop."
        % (parent, args.top, args.workers)
    )
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[watch] stopping...")
    finally:
        tracker.stop = True
        observer.stop()
        observer.join()
    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="wcm",
        description="West Coast Modern — hero-image selection pipeline.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  wcm doctor\n"
            "  wcm run /shoots/HarbourView --top 20 --workers 8\n"
            "  wcm run /shoots/HarbourView --resume\n"
            "  wcm watch /shoots --scan-existing\n"
            "  wcm watch /shoots --top 20 --workers 8\n"
        ),
    )
    sub = ap.add_subparsers(dest="command", metavar="COMMAND")
    sub.required = True

    # -- doctor --
    dp = sub.add_parser(
        "doctor",
        help="Check all prerequisites before your first run.",
        description=(
            "Validates:\n"
            "  • Python version (need 3.9+)\n"
            "  • All three dependencies installed (anthropic, Pillow, watchdog)\n"
            "  • ANTHROPIC_API_KEY is set\n"
            "  • API key authenticates with Anthropic\n"
            "  • SKILL.md is present next to hero_select.py\n\n"
            "Exit codes: 0 = all clear, 78 = configuration problem.\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    dp.set_defaults(func=cmd_doctor)

    # -- run --
    rp = sub.add_parser(
        "run",
        help="Run the two-stage pipeline on a single property folder.",
        description=(
            "Stage 1: score every image 0-60 with a fast model in parallel.\n"
            "Stage 2: send the top-N to a strong model for the full Hero Report.\n\n"
            "Outputs written into the property folder:\n"
            "  triage_scores.csv  — every image scored\n"
            "  hero_report.md     — the Hero Report\n"
            "  hero_report.html   — styled HTML version (open in browser)\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    rp.add_argument("folder", help="Path to the property photo folder")
    rp.add_argument(
        "--top", type=int, default=hs.DEFAULT_TOP_N, metavar="N",
        help="How many top-scoring images go to Stage 2 (default: %(default)s)",
    )
    rp.add_argument(
        "--workers", type=int, default=hs.DEFAULT_WORKERS, metavar="N",
        help="Parallel workers for Stage 1 triage (default: %(default)s)",
    )
    rp.add_argument(
        "--skill", default=None, metavar="PATH",
        help="Path to SKILL.md (default: SKILL.md next to hero_select.py)",
    )
    rp.add_argument(
        "--resume", action="store_true",
        help=(
            "Skip Stage 1 and reload triage scores from an existing "
            "triage_scores.csv — useful when Stage 1 finished but Stage 2 failed"
        ),
    )
    rp.set_defaults(func=cmd_run)

    # -- watch --
    wp = sub.add_parser(
        "watch",
        help="Watch a parent directory and auto-process new property subfolders.",
        description=(
            "Monitors a parent directory. When a new property subfolder appears\n"
            "and its contents stabilise for ~30 seconds (copy finished), the\n"
            "two-stage pipeline runs automatically. Folders that already have\n"
            "hero_report.md are skipped.\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    wp.add_argument("parent", help="Parent directory to watch")
    wp.add_argument(
        "--top", type=int, default=hs.DEFAULT_TOP_N, metavar="N",
        help="Passed through to 'run' (default: %(default)s)",
    )
    wp.add_argument(
        "--workers", type=int, default=hs.DEFAULT_WORKERS, metavar="N",
        help="Passed through to 'run' (default: %(default)s)",
    )
    wp.add_argument(
        "--skill", default=None, metavar="PATH",
        help="Path to SKILL.md (default: SKILL.md next to hero_select.py)",
    )
    wp.add_argument(
        "--scan-existing", action="store_true",
        help="Also process pre-existing subfolders that have no report yet",
    )
    wp.set_defaults(func=cmd_watch)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
