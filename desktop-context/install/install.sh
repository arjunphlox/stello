#!/usr/bin/env bash
# Stello desktop-context — installer.
#
# Idempotent. Safe to re-run. One command:
#   ./install/install.sh
#
# Creates user directories + config, builds the venv, installs deps, writes
# the LaunchAgent plist, and loads com.stello.context.
#
# Runs the user-space install only — no sudo, nothing system-wide.

set -euo pipefail

# -- Resolve paths -------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"
PYTHON="$VENV_DIR/bin/python"

WATCH_DIR="$HOME/Downloads/Stello Watcher"
APP_SUPPORT="$HOME/Library/Application Support/Stello"
DAEMON_DIR="$APP_SUPPORT/desktop-context"
THUMBS_DIR="$DAEMON_DIR/thumbs"
LOG_DIR="$APP_SUPPORT/logs"
CONFIG_DIR="$HOME/.config/stello"
CONFIG_FILE="$CONFIG_DIR/desktop-context.json"

PLIST_TEMPLATE="$SCRIPT_DIR/com.stello.context.plist.template"
PLIST_DEST="$HOME/Library/LaunchAgents/com.stello.context.plist"
LABEL="com.stello.context"
USER_UID="$(id -u)"
DOMAIN="gui/$USER_UID"

# -- Preflight -----------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[install] ERROR: macOS only."
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "[install] ERROR: uv not found. Install with: brew install uv"
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/pyproject.toml" ]]; then
  echo "[install] ERROR: expected pyproject.toml in $PROJECT_DIR"
  exit 1
fi

# -- Create directories --------------------------------------------------
mkdir -p "$WATCH_DIR"
mkdir -p "$DAEMON_DIR"
mkdir -p "$THUMBS_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

# -- Seed config (idempotent — never overwrites a user-edited file) ------
if [[ ! -f "$CONFIG_FILE" ]]; then
  cat >"$CONFIG_FILE" <<'JSON'
{
  "watched_folders": ["__WATCH_DIR__"],
  "max_file_size_mb": 50,
  "include_extensions": [".png", ".jpg", ".jpeg", ".webp", ".pdf", ".sketch", ".md", ".txt"],
  "ignore_globs": ["**/.DS_Store", "**/.git/**"],
  "poll_interval_s": 2,
  "activity_cache_ttl_s": 10,
  "dwell_window_s": 60,
  "vlm_images_per_window": 5,
  "safari_blocklist": [
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
    "stripe.com"
  ]
}
JSON
  python3 - "$CONFIG_FILE" "$WATCH_DIR" <<'PY'
import json, sys
path, watch_dir = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["watched_folders"] = [watch_dir]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
  echo "[install] wrote config:   $CONFIG_FILE"
else
  echo "[install] config exists:  $CONFIG_FILE  (not overwritten)"
fi

# -- Build venv + install package ----------------------------------------
echo "[install] project dir:    $PROJECT_DIR"
cd "$PROJECT_DIR"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "[install] creating venv:  $VENV_DIR"
  uv venv
else
  echo "[install] venv exists:    $VENV_DIR"
fi

echo "[install] installing deps (editable)…"
uv pip install -e .

if [[ ! -x "$PYTHON" ]]; then
  echo "[install] ERROR: venv python missing at $PYTHON"
  exit 1
fi

# -- Write LaunchAgent plist ---------------------------------------------
if [[ ! -f "$PLIST_TEMPLATE" ]]; then
  echo "[install] ERROR: missing template $PLIST_TEMPLATE"
  exit 1
fi

python3 - "$PLIST_TEMPLATE" "$PLIST_DEST" "$PYTHON" "$PROJECT_DIR" "$LOG_DIR" <<'PY'
import pathlib, sys
template, dest, python, work_dir, log_dir = map(pathlib.Path, sys.argv[1:6])
text = template.read_text()
text = (
    text.replace("__PYTHON__", str(python))
    .replace("__WORK_DIR__", str(work_dir))
    .replace("__LOG_DIR__", str(log_dir))
)
dest.write_text(text)
PY
echo "[install] wrote plist:    $PLIST_DEST"

# -- Load / reload LaunchAgent -------------------------------------------
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  echo "[install] unloading existing agent…"
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || launchctl bootout "$DOMAIN" "$PLIST_DEST" 2>/dev/null || true
fi

echo "[install] loading LaunchAgent…"
launchctl bootstrap "$DOMAIN" "$PLIST_DEST"

# -- Post-install checks -------------------------------------------------
sleep 4
CTX_OK=0
MLX_OK=0
if curl -sf "http://127.0.0.1:8766/healthz" >/dev/null; then
  CTX_OK=1
  echo "[install] daemon health:  ok (127.0.0.1:8766)"
else
  echo "[install] WARN: daemon not responding yet — check $LOG_DIR/stello-context.err.log"
fi

if curl -sf "http://127.0.0.1:8765/healthz" >/dev/null; then
  MLX_OK=1
  echo "[install] MLX health:     ok (127.0.0.1:8765)"
else
  echo "[install] WARN: MLX server not running — embed/vision enrichment will stall."
  echo "          Start com.stello.mlx first (see MLX Stack README)."
fi

# -- Summary -------------------------------------------------------------
echo
echo "[install] Done."
echo "  watcher folder:  $WATCH_DIR"
echo "  SQLite DB:       $APP_SUPPORT/desktop-context.db"
echo "  thumbnails:      $THUMBS_DIR/"
echo "  logs:            $LOG_DIR/"
echo "  config:          $CONFIG_FILE"
echo
echo "  curl http://127.0.0.1:8766/healthz"
echo "  curl 'http://127.0.0.1:8766/related?k=5'"
echo
echo "Permissions (macOS will prompt on first use — approve each):"
echo "  • Accessibility — for frontmost-app / window polling"
echo "  • Automation → Safari — for open-tab introspection"
echo "  • Automation → Sketch — for open-document + artboard export"
echo
echo "Sketch tip: keep Sketch in the foreground when testing visible-artboard"
echo "dwell — background Sketch windows report 0×0 size until activated."
echo
if [[ "$CTX_OK" -eq 1 && "$MLX_OK" -eq 1 ]]; then
  echo "Drop files into the watcher folder, open Sketch + Safari, then from"
  echo "localhost Stello DevTools: await stelloDesktop.fetchRelated(5)"
fi
