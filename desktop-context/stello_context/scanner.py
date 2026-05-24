"""FSEvents folder watcher + initial walk.

Uses watchdog's Observer (FSEvents-backed on macOS). Events are pushed
onto an asyncio.Queue from watchdog's own thread via
loop.call_soon_threadsafe — the queue is drained by the single enrich
worker in enrich.py.
"""
from __future__ import annotations

import asyncio
import fnmatch
import logging
import os
from pathlib import Path

from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

from .enrich import EnrichJob

logger = logging.getLogger("stello-context.scanner")


def _matches_extension(p: Path, exts: list[str]) -> bool:
    return p.suffix.lower() in {e.lower() for e in exts}


def _is_ignored(p: Path, ignore_globs: list[str]) -> bool:
    s = str(p)
    return any(
        fnmatch.fnmatch(s, g) or fnmatch.fnmatch(p.name, g) for g in ignore_globs
    )


def _eligible(p: Path, exts: list[str], ignores: list[str], max_bytes: int) -> bool:
    """Same filter applied by both initial_walk and the live handler."""
    if not p.is_file():
        return False
    if not _matches_extension(p, exts):
        return False
    if _is_ignored(p, ignores):
        return False
    try:
        if p.stat().st_size > max_bytes:
            return False
    except OSError:
        return False
    return True


class _Handler(FileSystemEventHandler):
    """Watchdog callback that bounces events into the asyncio queue.

    Called from watchdog's own thread, so we must use
    loop.call_soon_threadsafe to touch the asyncio queue.
    """

    def __init__(
        self,
        loop: asyncio.AbstractEventLoop,
        queue: asyncio.Queue,
        include_exts: list[str],
        ignore_globs: list[str],
        max_bytes: int,
    ):
        self.loop = loop
        self.queue = queue
        self.include_exts = include_exts
        self.ignore_globs = ignore_globs
        self.max_bytes = max_bytes

    def _maybe_enqueue(self, src_path: str, reason: str) -> None:
        # Resolve to the canonical absolute path so uniq_key matches whether
        # the event came from FSEvents (returns /private/tmp/...) or os.walk
        # (returns the user-supplied /tmp/... root). Without this, the same
        # file gets two distinct rows.
        try:
            p = Path(src_path).resolve()
        except OSError:
            return
        if not _eligible(p, self.include_exts, self.ignore_globs, self.max_bytes):
            return
        job = EnrichJob(source_path=str(p), reason=reason)
        self.loop.call_soon_threadsafe(self.queue.put_nowait, job)

    def on_created(self, event: FileSystemEvent) -> None:
        if event.is_directory:
            return
        self._maybe_enqueue(event.src_path, "fs_event:created")

    def on_modified(self, event: FileSystemEvent) -> None:
        if event.is_directory:
            return
        self._maybe_enqueue(event.src_path, "fs_event:modified")

    def on_moved(self, event: FileSystemEvent) -> None:
        if event.is_directory:
            return
        dest = getattr(event, "dest_path", None) or event.src_path
        self._maybe_enqueue(dest, "fs_event:moved")


def initial_walk(
    watched_folders: list[str],
    include_exts: list[str],
    ignore_globs: list[str],
    max_bytes: int,
    queue: asyncio.Queue,
) -> int:
    """Walk every watched folder once and enqueue eligible files.

    Called from the daemon's lifespan startup so it uses queue.put_nowait
    directly (no thread bouncing needed). Returns the enqueued count.
    """
    count = 0
    for wf in watched_folders:
        root = Path(wf)
        if not root.exists():
            logger.warning("watched folder missing: %s", wf)
            continue
        for dirpath, _dirnames, filenames in os.walk(root):
            for fn in filenames:
                # Resolve so the uniq_key matches what FSEvents will report
                # later (see _Handler._maybe_enqueue for the same reason).
                try:
                    p = (Path(dirpath) / fn).resolve()
                except OSError:
                    continue
                if not _eligible(p, include_exts, ignore_globs, max_bytes):
                    continue
                queue.put_nowait(EnrichJob(source_path=str(p), reason="initial_walk"))
                count += 1
    return count


def start_observer(
    loop: asyncio.AbstractEventLoop,
    queue: asyncio.Queue,
    watched_folders: list[str],
    include_exts: list[str],
    ignore_globs: list[str],
    max_bytes: int,
) -> Observer:
    """Boot the watchdog Observer on every watched folder.

    Returns the Observer so the caller can stop() + join() it on shutdown.
    """
    handler = _Handler(loop, queue, include_exts, ignore_globs, max_bytes)
    obs = Observer()
    for wf in watched_folders:
        if not Path(wf).exists():
            logger.warning("watched folder missing, skipping observer: %s", wf)
            continue
        obs.schedule(handler, wf, recursive=True)
        logger.info("watching: %s", wf)
    obs.start()
    return obs
