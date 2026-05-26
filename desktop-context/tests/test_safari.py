"""Safari tab + blocklist tests. The osascript call is monkeypatched so
nothing actually shells out — and Automation→Safari permission isn't
needed to run these."""
from __future__ import annotations

import json
import subprocess
from typing import Any

import pytest

from stello_context import safari


def test_hostname_of_basic() -> None:
    assert safari.hostname_of("https://Chase.com/login") == "chase.com"
    assert safari.hostname_of("http://mail.chase.com/inbox?x=1") == "mail.chase.com"
    assert safari.hostname_of("") == ""
    assert safari.hostname_of("not a url") == ""


def test_is_blocked_suffix_match() -> None:
    bl = ["chase.com", "localhost", "127.0.0.1"]
    assert safari.is_blocked("chase.com", bl)
    assert safari.is_blocked("mail.chase.com", bl)
    assert safari.is_blocked("CHASE.COM", bl)  # case-insensitive
    assert safari.is_blocked("localhost", bl)
    assert safari.is_blocked("127.0.0.1", bl)
    # Adversarial suffixes must NOT match.
    assert not safari.is_blocked("chase.com.attacker.com", bl)
    assert not safari.is_blocked("notchase.com", bl)
    assert not safari.is_blocked("localhost.example.com", bl)
    assert not safari.is_blocked("", bl)


def test_is_blocked_empty_blocklist_entry() -> None:
    """Blank lines in the blocklist must not match everything."""
    assert not safari.is_blocked("example.com", ["", "  "])


def test_filter_tabs_strips_blocked_url_and_title() -> None:
    tabs = [
        {"url": "https://tailwindcss.com/docs", "title": "Tailwind docs"},
        {"url": "https://chase.com/login", "title": "Chase — Sign in"},
        {"url": "https://mail.chase.com/inbox", "title": "Chase Mail"},
        {"url": "https://example.com/page", "title": "Example"},
    ]
    out = safari.filter_tabs(tabs, ["chase.com"])
    assert len(out) == 4
    assert out[0] == {
        "url": "https://tailwindcss.com/docs",
        "title": "Tailwind docs",
        "hostname": "tailwindcss.com",
        "blocked": False,
    }
    # Blocked tabs: url + title stripped, hostname preserved for audit.
    assert out[1]["url"] is None
    assert out[1]["title"] is None
    assert out[1]["hostname"] == "chase.com"
    assert out[1]["blocked"] is True
    assert out[2]["url"] is None
    assert out[2]["hostname"] == "mail.chase.com"
    assert out[2]["blocked"] is True
    assert out[3]["blocked"] is False


def _patch_osascript(monkeypatch: pytest.MonkeyPatch, *, stdout: str = "", returncode: int = 0, stderr: str = "") -> None:
    class _Proc:
        def __init__(self) -> None:
            self.returncode = returncode
            self.stdout = stdout
            self.stderr = stderr

    def _run(_cmd: list[str], **_kw: Any) -> _Proc:
        return _Proc()

    monkeypatch.setattr(subprocess, "run", _run)


def test_get_tabs_happy_path(monkeypatch: pytest.MonkeyPatch) -> None:
    payload = json.dumps([
        {"url": "https://tailwindcss.com/", "title": "Tailwind"},
        {"url": "https://chase.com/", "title": "Chase"},
    ])
    _patch_osascript(monkeypatch, stdout=payload)
    out = safari.get_tabs(["chase.com"])
    assert len(out) == 2
    assert out[0]["url"] == "https://tailwindcss.com/"
    assert out[1]["blocked"] is True and out[1]["url"] is None


def test_get_tabs_returns_empty_when_safari_not_running(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _patch_osascript(monkeypatch, stdout="[]")
    assert safari.get_tabs(["chase.com"]) == []


def test_get_tabs_handles_jxa_error_object(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _patch_osascript(monkeypatch, stdout=json.dumps({"error": "permission denied"}))
    assert safari.get_tabs([]) == []


def test_get_tabs_handles_non_json_output(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _patch_osascript(monkeypatch, stdout="hello world")
    assert safari.get_tabs([]) == []


def test_get_tabs_handles_nonzero_exit(monkeypatch: pytest.MonkeyPatch) -> None:
    _patch_osascript(monkeypatch, stdout="", returncode=1, stderr="exec error")
    assert safari.get_tabs([]) == []


def test_get_tabs_handles_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    def _raise(*_a: Any, **_kw: Any) -> Any:
        raise subprocess.TimeoutExpired(cmd="osascript", timeout=5.0)

    monkeypatch.setattr(subprocess, "run", _raise)
    assert safari.get_tabs([]) == []
