"""Context-poll unit tests. The OS adapters are monkeypatched so the suite
doesn't depend on PyObjC or Accessibility permission."""
from __future__ import annotations

import asyncio
import json
import sqlite3
from pathlib import Path

import pytest

from stello_context import context, store


def test_serialize_for_log_round_trips() -> None:
    snap = context.ContextSnapshot(
        ts=123.0,
        open_apps=[{"bundle_id": "com.apple.Safari", "name": "Safari", "active": True, "pid": 1}],
        frontmost_app="com.apple.Safari",
        frontmost_app_name="Safari",
        frontmost_window_title="Tailwind docs",
        ax_trusted=True,
    )
    raw = context.serialize_for_log(snap)
    payload = json.loads(raw)
    assert payload["frontmost_app"] == "com.apple.Safari"
    assert payload["frontmost_window_title"] == "Tailwind docs"
    assert payload["ax_trusted"] is True
    assert payload["open_apps"][0]["bundle_id"] == "com.apple.Safari"


def test_snapshot_dedupe_key_stable_across_pid_changes() -> None:
    """The dedupe key should ignore pids (they jitter on relaunch) and just
    care about (bundle ids set, frontmost app, frontmost title)."""
    a = context.ContextSnapshot(
        ts=1.0,
        open_apps=[{"bundle_id": "x", "name": "X", "active": True, "pid": 100}],
        frontmost_app="x",
        frontmost_window_title="title",
    )
    b = context.ContextSnapshot(
        ts=2.0,
        open_apps=[{"bundle_id": "x", "name": "X", "active": True, "pid": 200}],
        frontmost_app="x",
        frontmost_window_title="title",
    )
    assert context.snapshot_dedupe_key(a) == context.snapshot_dedupe_key(b)


def test_snapshot_dedupe_key_differs_on_title_change() -> None:
    a = context.ContextSnapshot(
        ts=1.0, open_apps=[], frontmost_app="x", frontmost_window_title="A"
    )
    b = context.ContextSnapshot(
        ts=2.0, open_apps=[], frontmost_app="x", frontmost_window_title="B"
    )
    assert context.snapshot_dedupe_key(a) != context.snapshot_dedupe_key(b)


def test_snapshot_to_dict_includes_all_fields() -> None:
    snap = context.ContextSnapshot(
        ts=5.0,
        open_apps=[{"bundle_id": "x", "name": "X", "active": False, "pid": 1}],
        frontmost_app="x",
        frontmost_app_name="X",
        frontmost_window_title="t",
        ax_trusted=False,
    )
    d = context.snapshot_to_dict(snap)
    assert d["ts"] == 5.0
    assert d["ax_trusted"] is False
    assert d["frontmost_app"] == "x"


def test_poll_loop_logs_only_on_change(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The poller writes to activity_log only when the dedupe key changes."""
    db = store.open_db(tmp_path / "ctx.db")

    snaps = [
        context.ContextSnapshot(ts=1.0, open_apps=[], frontmost_app="a", frontmost_window_title="t1"),
        context.ContextSnapshot(ts=2.0, open_apps=[], frontmost_app="a", frontmost_window_title="t1"),  # dup
        context.ContextSnapshot(ts=3.0, open_apps=[], frontmost_app="a", frontmost_window_title="t2"),  # change
        context.ContextSnapshot(ts=4.0, open_apps=[], frontmost_app="b", frontmost_window_title="t2"),  # change
    ]
    call = {"i": 0}

    async def fake_snap():
        s = snaps[call["i"]]
        call["i"] += 1
        if call["i"] >= len(snaps):
            # exhaust → trigger cancellation by raising
            asyncio.get_running_loop().call_soon(state_task.cancel)
        return s

    monkeypatch.setattr(context, "take_snapshot", fake_snap)

    class State:
        context_snapshot = None

    state = State()

    async def runner():
        global state_task
        state_task = asyncio.create_task(context.poll_loop(state, db, interval_s=0.01))
        try:
            await state_task
        except asyncio.CancelledError:
            pass

    asyncio.run(runner())

    rows = db.execute("SELECT open_apps FROM activity_log ORDER BY id").fetchall()
    # 3 distinct snapshots (first + two changes) ⇒ 3 rows
    assert len(rows) == 3
    titles = [json.loads(r["open_apps"])["frontmost_window_title"] for r in rows]
    assert titles == ["t1", "t2", "t2"]
    db.close()
