#!/usr/bin/env bash
# Stello desktop-context — installer.
#
# Idempotent. Safe to re-run. Steps grow as the daemon does:
#
#   Stage 1 (current): create directories + config + watcher folder.
#   Stage 2 (later):   build venv + install deps + write LaunchAgent + load.
#
# Runs the user-space install only — no sudo, nothing system-wide.

set -euo pipefail

# -- Paths ---------------------------------------------------------------
WATCH_DIR="$HOME/Downloads/Stello Watcher"
APP_SUPPORT="$HOME/Library/Application Support/Stello"
DAEMON_DIR="$APP_SUPPORT/desktop-context"
THUMBS_DIR="$DAEMON_DIR/thumbs"
LOG_DIR="$APP_SUPPORT/logs"
CONFIG_DIR="$HOME/.config/stello"
CONFIG_FILE="$CONFIG_DIR/desktop-context.json"

# -- Create directories --------------------------------------------------
mkdir -p "$WATCH_DIR"
mkdir -p "$DAEMON_DIR"
mkdir -p "$THUMBS_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"

# -- Seed config (idempotent — never overwrites a user-edited file) ------
if [[ ! -f "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" <<'JSON'
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
  # Substitute the watch dir path (single quotes above prevent $HOME expansion).
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

# -- Summary -------------------------------------------------------------
echo "[install] watcher folder: $WATCH_DIR"
echo "[install] app data:       $DAEMON_DIR/"
echo "[install] thumbnails:     $THUMBS_DIR/"
echo "[install] logs:           $LOG_DIR/"
echo
echo "[install] Stage 1 complete. Drop files into:"
echo "          $WATCH_DIR"
echo
echo "[install] Next: build the venv (step 3) and load the LaunchAgent (step 14)."
