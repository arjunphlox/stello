"""Open-apps + Accessibility poll.

A 2-second poll thread snapshots:
  - The list of regular (user-facing) running apps from NSWorkspace.
  - The current frontmost app (bundle id + pid + localized name).
  - The frontmost app's focused-window title via the Accessibility API.

The latest snapshot is held in memory (State.context_snapshot) for fast
reads from /context/now and /related (step 12). A snapshot is appended
to the activity_log table only when the serialised state changes — so
the table grows by app-switch, not by tick.

## Permission

The Accessibility API needs explicit user grant. macOS does NOT prompt
automatically for command-line Python processes; you must add the venv
Python binary to:

  System Settings → Privacy & Security → Accessibility

The binary path is `sys.executable` resolved through symlinks — for
uv-managed venvs that's
~/.local/share/uv/python/cpython-*-macos-*/bin/python3.*

When permission is missing, AXIsProcessTrusted() returns False;
focused-window title comes back as None. The daemon keeps running and
logs a single warning at startup.
"""
from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
import time
from dataclasses import asdict, dataclass, field
from typing import Any

from . import safari as safari_mod

logger = logging.getLogger("stello-context.context")

SAFARI_BUNDLE_ID = "com.apple.Safari"


@dataclass(frozen=True)
class ContextSnapshot:
    """In-memory snapshot of the current OS context."""

    ts: float
    open_apps: list[dict] = field(default_factory=list)
    frontmost_app: str | None = None  # bundle id
    frontmost_app_name: str | None = None
    frontmost_window_title: str | None = None
    ax_trusted: bool = False
    safari_tabs: list[dict] = field(default_factory=list)


# -- raw OS adapters ---------------------------------------------------------
# Each kept tiny so they can be monkeypatched in tests without needing to
# fake the entire PyObjC surface.


def ax_is_trusted() -> bool:
    """Synchronous check (does NOT prompt). Returns False if the host process
    isn't in the Accessibility allowlist."""
    try:
        from ApplicationServices import AXIsProcessTrusted
    except ImportError:
        return False
    return bool(AXIsProcessTrusted())


def frontmost_app() -> dict | None:
    """The current frontmost app, or None.

    Uses Quartz CGWindowList — the only API that returns LIVE on-screen
    window state from a long-running CLI process. NSWorkspace's
    frontmostApplication(), runningApplications().isActive(), and even
    menuBarOwningApplication() all rely on a notification cache that
    NEVER updates without an NSRunLoop pumping events in the host
    process. Verified 2026-05-25 against 11h of real app-switching
    (NSWorkspace stuck at boot value) and a follow-up live probe where
    a fresh process saw "sketch3" but the long-running daemon was still
    on "Safari".

    CGWindowList queries the WindowServer synchronously every call, so
    it's correct without any threading/runloop scaffolding.

    PID → bundle id lookup goes through
    NSRunningApplication.runningApplicationWithProcessIdentifier_, which
    IS live (it just resolves a PID against the process table, not the
    workspace notification cache).
    """
    try:
        from AppKit import NSRunningApplication
        from Quartz import (
            CGWindowListCopyWindowInfo,
            kCGNullWindowID,
            kCGWindowListExcludeDesktopElements,
            kCGWindowListOptionOnScreenOnly,
        )
    except ImportError:
        return None
    wins = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID,
    )
    if not wins:
        return None
    # Window list is z-ordered top→bottom. Take the first layer-0 (normal
    # application) window — that's whoever is currently frontmost on screen.
    for w in wins:
        if w.get("kCGWindowLayer", 0) != 0:
            continue
        pid = w.get("kCGWindowOwnerPID")
        if pid is None:
            continue
        owner_name = str(w.get("kCGWindowOwnerName") or "")
        # Live PID→bundle resolution: NSRunningApplication's class method,
        # NOT NSWorkspace (which doesn't have that selector).
        ra = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
        bid = str(ra.bundleIdentifier() or "") if ra else ""
        name = str(ra.localizedName() or "") if ra else owner_name
        return {"bundle_id": bid, "name": name, "pid": int(pid)}
    return None


def running_apps() -> list[dict]:
    """List of regular (NSApplicationActivationPolicyRegular) running apps.

    runningApplications() itself is live (kernel-backed). `active` is
    derived from frontmost_app()'s bundle id rather than
    NSRunningApplication.isActive() — the latter shares the stale-cache
    problem and would always report the boot-time active app.
    """
    try:
        from AppKit import NSApplicationActivationPolicyRegular, NSWorkspace
    except ImportError:
        return []
    ws = NSWorkspace.sharedWorkspace()
    front = frontmost_app()
    active_bid = front["bundle_id"] if front else None
    out: list[dict] = []
    for ra in ws.runningApplications():
        if ra.activationPolicy() != NSApplicationActivationPolicyRegular:
            continue
        bid = str(ra.bundleIdentifier() or "")
        out.append(
            {
                "bundle_id": bid,
                "name": str(ra.localizedName() or ""),
                "active": bid == active_bid,
                "pid": int(ra.processIdentifier()),
            }
        )
    return out


def focused_window_title(pid: int) -> str | None:
    """The focused-window title for an arbitrary app PID via AX.

    Returns None when Accessibility permission is missing, when the app
    has no window focused, or when the title attribute is absent.
    """
    try:
        from ApplicationServices import (
            AXUIElementCopyAttributeValue,
            AXUIElementCreateApplication,
            kAXFocusedWindowAttribute,
            kAXTitleAttribute,
        )
    except ImportError:
        return None
    app_elem = AXUIElementCreateApplication(pid)
    err, window = AXUIElementCopyAttributeValue(app_elem, kAXFocusedWindowAttribute, None)
    if err != 0 or window is None:
        return None
    err, title = AXUIElementCopyAttributeValue(window, kAXTitleAttribute, None)
    if err != 0 or title is None:
        return None
    return str(title)


# -- snapshot composition ----------------------------------------------------


async def take_snapshot(safari_blocklist: list[str] | None = None) -> ContextSnapshot:
    """Compose a ContextSnapshot. All OS calls bounced to a worker thread
    so they don't block the asyncio loop.

    Safari tabs are fetched only when Safari is actually running (no point
    triggering an osascript-to-Safari prompt when Safari isn't open).
    `safari_blocklist=None` skips Safari introspection entirely; pass the
    config list to enable.
    """
    apps = await asyncio.to_thread(running_apps)
    front = await asyncio.to_thread(frontmost_app)
    trusted = await asyncio.to_thread(ax_is_trusted)
    title: str | None = None
    if trusted and front is not None:
        title = await asyncio.to_thread(focused_window_title, front["pid"])
    tabs: list[dict] = []
    if safari_blocklist is not None and any(
        a.get("bundle_id") == SAFARI_BUNDLE_ID for a in apps
    ):
        tabs = await asyncio.to_thread(safari_mod.get_tabs, safari_blocklist)
    return ContextSnapshot(
        ts=time.time(),
        open_apps=apps,
        frontmost_app=front["bundle_id"] if front else None,
        frontmost_app_name=front["name"] if front else None,
        frontmost_window_title=title,
        ax_trusted=trusted,
        safari_tabs=tabs,
    )


def snapshot_dedupe_key(snap: ContextSnapshot) -> str:
    """JSON string used to detect "the world changed since last tick" —
    feeds into the activity_log dedup. Includes the set of non-blocked
    Safari tab URLs so tab changes also create new rows (the activity
    classifier in step 12 needs that signal)."""
    return json.dumps(
        {
            "apps": sorted(a["bundle_id"] for a in snap.open_apps),
            "front": snap.frontmost_app,
            "title": snap.frontmost_window_title,
            "tabs": sorted(t["url"] for t in snap.safari_tabs if t.get("url")),
        },
        sort_keys=True,
    )


def serialize_for_log(snap: ContextSnapshot) -> str:
    """Richer JSON for the activity_log.open_apps TEXT column."""
    return json.dumps(
        {
            "open_apps": snap.open_apps,
            "frontmost_app": snap.frontmost_app,
            "frontmost_app_name": snap.frontmost_app_name,
            "frontmost_window_title": snap.frontmost_window_title,
            "ax_trusted": snap.ax_trusted,
        }
    )


def serialize_safari_tabs(snap: ContextSnapshot) -> str:
    """JSON for the activity_log.safari_tabs TEXT column.
    Blocked tabs are persisted as {hostname, blocked:true} only —
    URL/title are stripped at filter_tabs() and never reach this row."""
    return json.dumps(snap.safari_tabs)


def snapshot_to_dict(snap: ContextSnapshot) -> dict[str, Any]:
    """For /context/now JSON response."""
    return asdict(snap)


# -- poll loop ---------------------------------------------------------------


async def poll_loop(
    state: Any,  # daemon.State — typed loosely to avoid circular import
    db: sqlite3.Connection,
    interval_s: float,
    safari_blocklist: list[str] | None = None,
) -> None:
    """Long-running task. Updates state.context_snapshot every tick,
    logs to activity_log only when the dedupe key changes."""
    logger.info(
        "context poll started (interval=%.1fs, safari=%s)",
        interval_s,
        "on" if safari_blocklist is not None else "off",
    )
    last_key: str | None = None
    warned_untrusted = False
    while True:
        try:
            snap = await take_snapshot(safari_blocklist=safari_blocklist)
            state.context_snapshot = snap
            if not snap.ax_trusted and not warned_untrusted:
                logger.warning(
                    "Accessibility permission NOT granted — focused-window titles "
                    "will be None. Grant via System Settings → Privacy & Security → "
                    "Accessibility for the Python binary that's running this daemon."
                )
                warned_untrusted = True
            key = snapshot_dedupe_key(snap)
            if key != last_key:
                db.execute(
                    "INSERT INTO activity_log(ts, open_apps, safari_tabs) "
                    "VALUES(?, ?, ?)",
                    (
                        snap.ts,
                        serialize_for_log(snap),
                        serialize_safari_tabs(snap),
                    ),
                )
                last_key = key
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            logger.exception("context poll: unhandled exception")
        await asyncio.sleep(interval_s)
