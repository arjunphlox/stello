"""SQLite store tests — schema, transactions, basic CRUD."""
from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from stello_context import store


def test_open_db_creates_schema(tmp_path: Path) -> None:
    db_path = tmp_path / "ctx.db"
    conn = store.open_db(db_path)
    try:
        assert db_path.exists()
        tables = {
            r[0]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert {"items", "activity_log", "caption_cache", "schema_meta"} <= tables
        assert store.schema_version(conn) == 1
    finally:
        conn.close()


def test_insert_and_counts(tmp_path: Path) -> None:
    conn = store.open_db(tmp_path / "c.db")
    try:
        conn.execute(
            "INSERT INTO items(kind, source_path, uniq_key, type, status) "
            "VALUES(?,?,?,?,?)",
            ("file", "/x/a.md", "/x/a.md", "text", "ready"),
        )
        conn.execute(
            "INSERT INTO items(kind, source_path, uniq_key, type, status) "
            "VALUES(?,?,?,?,?)",
            ("file", "/x/b.png", "/x/b.png", "image", "pending_vlm"),
        )
        counts = store.counts_by_status(conn)
        assert counts == {"ready": 1, "pending_vlm": 1}
    finally:
        conn.close()


def test_uniq_key_enforced(tmp_path: Path) -> None:
    conn = store.open_db(tmp_path / "u.db")
    try:
        conn.execute(
            "INSERT INTO items(kind, source_path, uniq_key, type, status) "
            "VALUES(?,?,?,?,?)",
            ("file", "/x/a.md", "/x/a.md", "text", "ready"),
        )
        with pytest.raises(sqlite3.IntegrityError):
            conn.execute(
                "INSERT INTO items(kind, source_path, uniq_key, type, status) "
                "VALUES(?,?,?,?,?)",
                ("file", "/x/a.md", "/x/a.md", "text", "ready"),
            )
    finally:
        conn.close()


def test_idempotent_open(tmp_path: Path) -> None:
    """Re-opening an existing DB must not error and must preserve data."""
    p = tmp_path / "i.db"
    conn = store.open_db(p)
    conn.execute(
        "INSERT INTO items(kind, source_path, uniq_key, type, status) "
        "VALUES(?,?,?,?,?)",
        ("file", "/x/a.md", "/x/a.md", "text", "ready"),
    )
    conn.close()

    conn = store.open_db(p)
    try:
        assert store.schema_version(conn) == 1
        row = conn.execute("SELECT COUNT(*) AS n FROM items").fetchone()
        assert row["n"] == 1
    finally:
        conn.close()


def test_transaction_rollback(tmp_path: Path) -> None:
    conn = store.open_db(tmp_path / "t.db")
    try:
        with pytest.raises(RuntimeError):
            with store.transaction(conn):
                conn.execute(
                    "INSERT INTO items(kind, source_path, uniq_key, type, status) "
                    "VALUES(?,?,?,?,?)",
                    ("file", "/x/a.md", "/x/a.md", "text", "ready"),
                )
                raise RuntimeError("boom")
        # Row should NOT be present after rollback.
        n = conn.execute("SELECT COUNT(*) AS n FROM items").fetchone()["n"]
        assert n == 0
    finally:
        conn.close()
