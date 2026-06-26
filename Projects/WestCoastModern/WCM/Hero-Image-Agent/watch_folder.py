#!/usr/bin/env python3
"""West Coast Modern — local folder watcher for the hero-selection pipeline.

Watches a PARENT directory. When a new property subfolder appears and its
contents stop changing for ~30s (i.e. the copy/upload finished), it runs the
same two-stage engine (hero_select.process_folder) on that subfolder.

    python3 watch_folder.py /path/to/Parent [--top 12] [--workers 5] [--scan-existing]

Robustness:
  - Debounces on folder-size stability (count + total bytes), ignoring the
    engine's own output files so a finished run doesn't look like a change.
  - Per-folder in-progress lock so a folder is never processed twice at once.
  - Skips any folder that already has hero_report.md (durable guard).
  - Ignores events for its own output files (no self-trigger loop).
"""
from __future__ import annotations

import argparse
import sys
import threading
import time
from pathlib import Path

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

import hero_select as hs

STABLE_SECONDS = 30   # folder must be unchanged this long before processing
POLL_SECONDS = 5      # how often the monitor thread checks stability


class FolderTracker:
    """Tracks candidate subfolders and processes them once stable."""

    def __init__(self, parent, client, top_n, workers, skill_path):
        self.parent = Path(parent).resolve()
        self.client = client
        self.top_n = top_n
        self.workers = workers
        self.skill_path = skill_path

        self.lock = threading.Lock()
        self.pending = {}      # child_path -> first-seen timestamp
        self.processing = set()
        self.stop = False

    def _child_of(self, event_path):
        """Map an event path to the immediate property subfolder of parent."""
        p = Path(event_path).resolve()
        try:
            rel = p.relative_to(self.parent)
        except ValueError:
            return None
        if not rel.parts:
            return None
        child = self.parent / rel.parts[0]
        return child if child.is_dir() else None

    def mark(self, event_path):
        child = self._child_of(event_path)
        if child is None:
            return
        with self.lock:
            if child in self.processing:
                return
            if (child / hs.REPORT_NAME).exists():
                return  # already done
            self.pending.setdefault(child, time.time())

    def folder_signature(self, child):
        """(image-relevant file count, total bytes), ignoring our own outputs."""
        count = 0
        total = 0
        for p in child.rglob("*"):
            if not p.is_file() or p.name in hs.OUTPUT_NAMES or p.name.startswith("."):
                continue
            try:
                total += p.stat().st_size
                count += 1
            except OSError:
                pass
        return (count, total)

    def monitor_loop(self):
        state = {}  # child -> [last_signature, last_change_ts]
        while not self.stop:
            time.sleep(POLL_SECONDS)
            with self.lock:
                children = list(self.pending.keys())

            for child in children:
                if not child.is_dir():
                    with self.lock:
                        self.pending.pop(child, None)
                    state.pop(child, None)
                    continue
                if (child / hs.REPORT_NAME).exists():
                    with self.lock:
                        self.pending.pop(child, None)
                    state.pop(child, None)
                    continue

                sig = self.folder_signature(child)
                if child not in state or state[child][0] != sig:
                    state[child] = [sig, time.time()]   # changed — reset timer
                    continue
                if sig[0] == 0:
                    continue  # no real files yet
                if time.time() - state[child][1] < STABLE_SECONDS:
                    continue  # not stable long enough

                # Stable -> claim and process off-thread.
                with self.lock:
                    if child in self.processing:
                        continue
                    self.processing.add(child)
                    self.pending.pop(child, None)
                state.pop(child, None)
                threading.Thread(target=self._process, args=(child,),
                                 daemon=True).start()

    def _process(self, child):
        try:
            print("[watch] processing %s" % child)
            hs.process_folder(
                self.client, child,
                top_n=self.top_n, workers=self.workers,
                skill_path=self.skill_path, skip_if_done=True,
            )
            print("[watch] done %s" % child)
        except (Exception, SystemExit) as e:  # never let one folder kill the watcher
            sys.stderr.write("[watch] error processing %s: %s\n" % (child, e))
        finally:
            with self.lock:
                self.processing.discard(child)

    def seed_existing(self):
        """Queue pre-existing unprocessed subfolders (for --scan-existing)."""
        for child in sorted(self.parent.iterdir()):
            if child.is_dir() and not (child / hs.REPORT_NAME).exists():
                with self.lock:
                    self.pending.setdefault(child, time.time())


class _Handler(FileSystemEventHandler):
    def __init__(self, tracker):
        self.tracker = tracker

    def on_any_event(self, event):
        if Path(event.src_path).name in hs.OUTPUT_NAMES:
            return  # ignore our own writes — no self-trigger
        self.tracker.mark(event.src_path)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Watch a parent directory and run hero selection on new "
                    "property subfolders.")
    ap.add_argument("parent", help="Parent directory to watch")
    ap.add_argument("--top", type=int, default=hs.DEFAULT_TOP_N)
    ap.add_argument("--workers", type=int, default=hs.DEFAULT_WORKERS)
    ap.add_argument("--skill", default=None,
                    help="Path to SKILL.md (default: next to hero_select.py)")
    ap.add_argument("--scan-existing", action="store_true",
                    help="Also process pre-existing unprocessed subfolders on start")
    args = ap.parse_args(argv)

    try:  # live progress even when stdout is piped (e.g. launchd logs)
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    parent = Path(args.parent)
    if not parent.is_dir():
        sys.stderr.write("ERROR: not a directory: %s\n" % parent)
        return 1

    client = hs.make_client()  # fails clearly if ANTHROPIC_API_KEY is missing

    tracker = FolderTracker(parent, client, args.top, args.workers, args.skill)
    if args.scan_existing:
        tracker.seed_existing()

    observer = Observer()
    observer.schedule(_Handler(tracker), str(parent.resolve()), recursive=True)
    observer.start()

    monitor = threading.Thread(target=tracker.monitor_loop, daemon=True)
    monitor.start()

    print("[watch] watching %s (stable=%ds, top=%d, workers=%d). Ctrl-C to stop."
          % (parent, STABLE_SECONDS, args.top, args.workers))
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


if __name__ == "__main__":
    sys.exit(main())
