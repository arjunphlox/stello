"""Safari tab introspection via JXA (JavaScript for Automation) + hostname-
suffix blocklist.

Tabs are CONTEXT only — never written to items, never embedded as
candidates, never returned in /related results. We extract URL + title
so the activity classifier (step 12) can describe what the user is
doing across their open tabs.

## Blocklist semantics

Suffix match on hostname, case-insensitive:
  - `chase.com` matches `chase.com` AND `mail.chase.com`
  - `localhost` matches `localhost` only (no dot suffix)
  - `127.0.0.1` matches `127.0.0.1` only

Blocked tabs survive in the snapshot with `blocked: True` and their
hostname preserved (so it's possible to audit what was filtered), but
their `url` and `title` are explicitly set to None — never embedded,
never written to SQLite as plaintext, never returned over the API.

## Permission

First call to `osascript` against Safari triggers a macOS Automation
prompt ("Allow Python to control Safari"). If denied or unanswered,
get_tabs() returns [] and logs a single warning per failure mode.
"""
from __future__ import annotations

import json
import logging
import subprocess
from urllib.parse import urlparse

logger = logging.getLogger("stello-context.safari")

# JXA script: enumerate every tab in every window. JSON output is much
# cleaner to parse than AppleScript's nested-list dialect.
JXA_SCRIPT = """
function run() {
  try {
    const Safari = Application('Safari');
    if (!Safari.running()) return JSON.stringify([]);
    const out = [];
    Safari.windows().forEach(function(w) {
      try {
        w.tabs().forEach(function(t) {
          try {
            out.push({url: String(t.url() || ''), title: String(t.name() || '')});
          } catch (e) {}
        });
      } catch (e) {}
    });
    return JSON.stringify(out);
  } catch (e) {
    return JSON.stringify({error: String(e)});
  }
}
"""


def _run_osascript(script: str, timeout_s: float = 5.0) -> str:
    """Run a JXA script via `osascript -l JavaScript -e <script>`."""
    proc = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"osascript exit {proc.returncode}: {proc.stderr.strip()!r}"
        )
    return proc.stdout.strip()


def hostname_of(url: str) -> str:
    """Lowercased hostname from a URL, or '' on parse failure / no host."""
    if not url:
        return ""
    try:
        return (urlparse(url).hostname or "").lower()
    except ValueError:
        return ""


def is_blocked(hostname: str, blocklist: list[str]) -> bool:
    """Suffix-match (case-insensitive).

    `mail.chase.com` matches `chase.com`; `chase.com.attacker` does NOT.
    """
    if not hostname:
        return False
    h = hostname.lower()
    for b in blocklist:
        bl = b.lower().strip()
        if not bl:
            continue
        if h == bl or h.endswith("." + bl):
            return True
    return False


def filter_tabs(tabs: list[dict], blocklist: list[str]) -> list[dict]:
    """Apply blocklist; blocked tabs lose url + title (never embedded /
    logged / persisted). Hostname is preserved for audit."""
    out: list[dict] = []
    for t in tabs:
        url = str(t.get("url") or "")
        title = str(t.get("title") or "")
        host = hostname_of(url)
        if is_blocked(host, blocklist):
            out.append({"url": None, "title": None, "hostname": host, "blocked": True})
        else:
            out.append({"url": url, "title": title, "hostname": host, "blocked": False})
    return out


def get_tabs(blocklist: list[str], timeout_s: float = 5.0) -> list[dict]:
    """Live Safari tab list, blocklist applied.

    Returns [{url, title, hostname, blocked}, ...] — empty when Safari
    isn't running, permission was denied, or the script failed.
    """
    try:
        raw = _run_osascript(JXA_SCRIPT, timeout_s=timeout_s)
    except subprocess.TimeoutExpired:
        logger.warning("safari: osascript timed out after %.1fs", timeout_s)
        return []
    except FileNotFoundError:
        logger.warning("safari: osascript not on PATH")
        return []
    except RuntimeError as e:
        logger.warning("safari: %s", e)
        return []

    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        logger.warning("safari: non-JSON osascript output: %r", raw[:200])
        return []
    if isinstance(data, dict) and "error" in data:
        logger.warning("safari: JXA error: %s", data["error"])
        return []
    if not isinstance(data, list):
        return []

    return filter_tabs(data, blocklist)
