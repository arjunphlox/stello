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

## Format v2 (decided 2026-11-27, before phase 1)

Nothing is stored twice; shared things exist once and are referenced by id.

- **Entity files:** `people/<slug>.md`, `places/<slug>.md`, `collections/<slug>.md`, each with an `id`, name, aliases and kind facts. Items list them by id (`people: [...]`, `places: [...]`). Only the item records the link; each app's index builds the reverse view.
- **Your files are referenced, not copied:** an item made from a dropped-in image or PDF has `file:` pointing at the original. `media/` holds only what Stello downloaded.
- **One item per thing:** links matched on the normalised URL, files on a content hash, people and places on name + aliases (+ coordinates). A repeat sighting adds to `sources:` on the existing item.
- **Month folders:** `items/<year>/<month>/` by the real first-saved date; imports keep dates from the CSV, bookmark file or file.
- **Ids, not paths:** renaming or moving files never breaks links.

The v1 export from 2026-11-26 is converted once by a script at the start of phase 1.

### Built (phase 1, part 1)

`src/lib/folder-v2.js` + `scripts/convert-folder-v2.mjs` (tests: `test/folder-v2.test.js`).

- Items of kind individual, studio and foundry become `people/` files (same id). Header `author`, `meta.author/maker/brand`, `meta.typeDesigner`, `meta.typeFoundry` become `people: [{id, role}]`, matched by name and aliases.
- `location` tags and `meta.location/geography` become `places: [ids]`; `collection` tags become `collections: [ids]`. They leave `tags`/`meta`, so nothing is held twice.
- Bodies drop a `## Summary` section equal to the summary and a `## Key Snippets` section whose quotes are all header snippets. Other text stays.
- One item per normalised URL; a repeat adds a `sources:` entry and its snippets, images, tags and notes.
- Run: trial first (writes to a temp folder), then `--apply` (moves v1 files into `.stello-v1/`, deletes nothing). `export-folder.mjs` refuses a v2 folder.

