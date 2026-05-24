"""Config loader tests — verify defaults, file load, env-var override."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from stello_context import config as cfg


def test_defaults_when_file_missing(tmp_path: Path) -> None:
    c = cfg.load(tmp_path / "does-not-exist.json")
    assert c.watched_folders, "default watched_folders should be non-empty"
    assert c.dwell_window_s == 60
    assert c.vlm_images_per_window == 5
    assert "localhost" in c.safari_blocklist
    assert "stello.arjunphlox.com" in c.safari_blocklist
    assert "chase.com" in c.safari_blocklist


def test_load_from_file(tmp_path: Path) -> None:
    p = tmp_path / "cfg.json"
    p.write_text(
        json.dumps(
            {
                "watched_folders": ["/tmp/foo"],
                "dwell_window_s": 30,
                "vlm_images_per_window": 3,
                "safari_blocklist": ["example.com"],
            }
        )
    )
    c = cfg.load(p)
    assert c.watched_folders == ["/tmp/foo"]
    assert c.dwell_window_s == 30
    assert c.vlm_images_per_window == 3
    assert c.safari_blocklist == ["example.com"]
    # Unspecified fields keep their defaults
    assert c.poll_interval_s == 2
    assert c.max_file_size_mb == 50


def test_env_var_override(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    p = tmp_path / "envcfg.json"
    p.write_text(json.dumps({"dwell_window_s": 99}))
    monkeypatch.setenv("STELLO_CTX_CONFIG", str(p))
    c = cfg.load()
    assert c.dwell_window_s == 99


def test_partial_config_keeps_defaults(tmp_path: Path) -> None:
    """A partial JSON file should override only the keys it sets."""
    p = tmp_path / "partial.json"
    p.write_text(json.dumps({"safari_blocklist": ["only.example"]}))
    c = cfg.load(p)
    assert c.safari_blocklist == ["only.example"]
    assert c.dwell_window_s == 60  # untouched
    assert c.vlm_images_per_window == 5  # untouched
