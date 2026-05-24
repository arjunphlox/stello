"""Scanner unit tests — extension filter, ignore globs, max bytes, walk."""
from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from stello_context import scanner


def test_matches_extension() -> None:
    assert scanner._matches_extension(Path("/x/a.md"), [".md", ".txt"])
    assert scanner._matches_extension(Path("/x/A.MD"), [".md"])  # case-insensitive
    assert not scanner._matches_extension(Path("/x/a.pdf"), [".md", ".txt"])


def test_is_ignored() -> None:
    assert scanner._is_ignored(Path("/x/.DS_Store"), ["**/.DS_Store"])
    assert scanner._is_ignored(Path("/x/.git/foo"), ["**/.git/**"])
    assert not scanner._is_ignored(Path("/x/a.md"), ["**/.git/**"])


def test_eligible_skips_directory(tmp_path: Path) -> None:
    d = tmp_path / "sub"
    d.mkdir()
    assert not scanner._eligible(d, [".md"], [], 10_000)


def test_eligible_skips_oversize(tmp_path: Path) -> None:
    p = tmp_path / "huge.md"
    p.write_bytes(b"x" * 2000)
    assert not scanner._eligible(p, [".md"], [], 1000)
    assert scanner._eligible(p, [".md"], [], 5000)


def test_initial_walk_finds_eligible_files(tmp_path: Path) -> None:
    (tmp_path / "a.md").write_text("hello")
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "b.txt").write_text("world")
    (tmp_path / "noise.bin").write_bytes(b"\x00" * 100)
    (tmp_path / ".DS_Store").write_bytes(b"junk")

    queue: asyncio.Queue = asyncio.Queue()
    count = scanner.initial_walk(
        [str(tmp_path)],
        include_exts=[".md", ".txt"],
        ignore_globs=["**/.DS_Store"],
        max_bytes=10_000,
        queue=queue,
    )
    assert count == 2
    enqueued = sorted(queue.get_nowait().source_path for _ in range(count))
    assert any(s.endswith("a.md") for s in enqueued)
    assert any(s.endswith("b.txt") for s in enqueued)


def test_initial_walk_missing_folder_does_not_raise(tmp_path: Path) -> None:
    queue: asyncio.Queue = asyncio.Queue()
    count = scanner.initial_walk(
        [str(tmp_path / "nope")],
        include_exts=[".md"],
        ignore_globs=[],
        max_bytes=1000,
        queue=queue,
    )
    assert count == 0


def test_initial_walk_resolves_symlinks(tmp_path: Path) -> None:
    """A watched folder reached via symlink must produce the same uniq_key
    that FSEvents will later emit (the symlink-resolved canonical path).
    Regression: macOS /tmp -> /private/tmp produced duplicate rows.
    """
    real = tmp_path / "real"
    real.mkdir()
    (real / "note.md").write_text("hi")
    link = tmp_path / "link"
    link.symlink_to(real)

    queue: asyncio.Queue = asyncio.Queue()
    count = scanner.initial_walk(
        [str(link)],
        include_exts=[".md"],
        ignore_globs=[],
        max_bytes=1000,
        queue=queue,
    )
    assert count == 1
    job = queue.get_nowait()
    # The enqueued path must point at the canonical location, not the symlink,
    # so it matches what watchdog/FSEvents resolves to.
    assert job.source_path == str((real / "note.md").resolve())
