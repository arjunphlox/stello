# Stello as a folder engine

Plan (living doc): https://claude.ai/artifact/A97hwwSBdXeJhnT5mnJ5PW. Decided with Arjun on 2026-11-25.

- The user's folder is the only source of truth: one Markdown file per item, images beside it, canvases as JSON Canvas. Each app keeps its own rebuildable index; nothing derived lives in the folder.
- Sources: iCloud Drive (Apple apps' default), Google Drive and Dropbox. The web reaches Drive and Dropbox through their APIs, and an iCloud folder only through File System Access in Chrome-family desktop browsers.
- The Worker becomes a stateless engine (`/read`, `/fetch-image`). D1, R2, CF Images, the sync bridge, accounts and CloudKit go in the last phase, only on Arjun's explicit go.
- Phases: 0 export, 1 engine package, 2 Mac + web on the folder (beside D1), 3 iPad/iPhone + Drive/Dropbox, 4 cut over and delete.

## Phase 0: export (this PR)

Format: `src/lib/folder-format.js` (version 1), tests in `test/folder-format.test.js`.

```
<folder>/
  stello.json                 format, version, counts
  items/<year>/<slug>.md      header (one JSON value per line, valid YAML) + the item's Markdown body
  media/<slug>/<n>.<ext>      images as stored in R2 (no re-encoding)
  projects/<name>.canvas      JSON Canvas; the full Stello canvas doc under "stello"
  export-report.json          counts, failed images, round-trip check
```

Run (read-only; pairs through /pair.html, revokes its token at the end):

```
node scripts/export-folder.mjs --out "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Stello"
```

Every exported item is parsed back from its file and compared with the API copy; mismatches land in `export-report.json`. The 2026-11-05 JSON export (3,605 items) round-trips with zero mismatches.
