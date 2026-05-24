"""Config loader for ~/.config/stello/desktop-context.json.

Pydantic model with sensible defaults so the daemon can boot even if the
file is missing or partial. Overridable via env var STELLO_CTX_CONFIG.

Hot-reload (SIGHUP / file-watch) lands later — for now we load once at
daemon startup.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

from pydantic import BaseModel, Field

DEFAULT_CONFIG_PATH = Path("~/.config/stello/desktop-context.json").expanduser()
DEFAULT_WATCH_DIR = str(Path("~/Downloads/Stello Watcher").expanduser())

# Baseline blocklist: Stello's own surfaces + the common US banking / fintech
# hosts. Users edit the JSON file to add their own.
DEFAULT_BLOCKLIST = [
    "stello.arjunphlox.com",
    "localhost",
    "127.0.0.1",
    "chase.com",
    "bankofamerica.com",
    "wellsfargo.com",
    "citi.com",
    "ally.com",
    "capitalone.com",
    "americanexpress.com",
    "schwab.com",
    "fidelity.com",
    "vanguard.com",
    "robinhood.com",
    "venmo.com",
    "paypal.com",
    "wise.com",
    "revolut.com",
    "stripe.com",
]


class Config(BaseModel):
    """Runtime config. All fields have defaults; the JSON file overrides any subset."""

    watched_folders: list[str] = Field(default_factory=lambda: [DEFAULT_WATCH_DIR])
    max_file_size_mb: int = 50
    include_extensions: list[str] = Field(
        default_factory=lambda: [
            ".png", ".jpg", ".jpeg", ".webp", ".pdf", ".sketch", ".md", ".txt"
        ]
    )
    ignore_globs: list[str] = Field(
        default_factory=lambda: ["**/.DS_Store", "**/.git/**"]
    )
    poll_interval_s: int = 2
    activity_cache_ttl_s: int = 10
    dwell_window_s: int = 60
    vlm_images_per_window: int = 5
    safari_blocklist: list[str] = Field(default_factory=lambda: list(DEFAULT_BLOCKLIST))


def load(path: Path | None = None) -> Config:
    """Load config from disk.

    Resolution order: explicit `path` arg → $STELLO_CTX_CONFIG → DEFAULT_CONFIG_PATH.
    Missing file → all-defaults (not an error — daemon still boots).
    Invalid JSON → raises (we want the daemon to crash loudly here).
    """
    p = path if path is not None else Path(
        os.environ.get("STELLO_CTX_CONFIG", str(DEFAULT_CONFIG_PATH))
    )
    if not p.exists():
        return Config()
    with open(p) as f:
        data = json.load(f)
    return Config(**data)
