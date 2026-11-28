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

### Built (phase 1, part 2)

- `engine/index.js`: one entry for the engine. `read()` turns a link (or HTML the app fetched) into a v2 item header: kind + typed meta from the readers, rule tags, images, and people/places/collections as names for the caller to match (`matchEntity`). Also re-exports `related`/`layer1`/`search`, `ruleTags`, the dedupe helpers and both folder formats. No D1, no R2.
- Worker: `POST /api/read` and `GET /api/fetch-image?url=` (`src/routes/read.js`), stateless. Signed-in for now; phase 4 swaps auth for a per-install key + rate limit. The image proxy only fetches public http(s) images, 10 MB max, no SVG.
- `scripts/export-folder.mjs` writes v2 (the same converter runs in memory), refuses a v1 folder, and lists files it didn't produce instead of deleting them. Re-running on an unchanged library writes nothing.
- `meta.publishedAt` and similar dates are Apple reference-date seconds (since 2001-01-01), as the readers have always stored them, not a bug.


## Multiple folders (decided 2026-11-28, plan doc section 4b)

The library is every folder the person adds, merged into one grid. Settings lists the folders (add, replace, remove; one takes new saves) and each item's Summary shows a Folder row per folder holding its file.

- An item's folder comes from where its file sits (each app's index), never from the file. Item ids are global, so canvases and the plugin keep working.
- Remove only forgets the folder; its files are untouched. Replace points an entry at a moved or renamed copy.
- The same item in two folders is one card listing both folders. Copies that differ merge like sync conflict copies (tags and links combine, newer field wins, both notes kept), written to the main (first-added) copy. Deleting moves every copy to its own folder's `.trash/`.
- On Add, the person chooses per folder: Stello items only, or also turn its Markdown, CSV, PDF, bookmarks and images into items.
- The folder list is shared across Mac, iPad and iPhone through iCloud; each browser keeps its own.
- The Folder row opens the file where the platform allows: Finder on Mac, Files on iPad and iPhone, Drive and Dropbox on their sites; a local or iCloud folder on the web copies its path.
- Edge cases (unreachable, nested folders, read-only copies, v1 folders): plan doc section 4b.

### Built (phase 2, part 1: read-only)

- Web: `folders.js` (File System Access, Chromium desktop) keeps folder handles + an id → path index in IndexedDB and re-reads only changed files; Settings › Folders and the Summary Folder row (`panel-layout.js` `opts.folders`). Tests: `test/folders.test.js`.
- Apple: `Store/FolderSources.swift` (security-scoped bookmarks, index in Application Support, re-read on launch/activate), Settings › Folders in `UserPreferencesContent.swift`, Folder row in `CardSubcards.swift`. Tests: `StelloTests/FolderSourcesTests.swift`.

### Built (phase 2, part 2: writes)

- Folder access is read-write: the web asks the browser again (`mode: 'readwrite'`); on the Mac a folder added in part 1 has a read-only bookmark and shows "Allow writing" (pick it once more). Until then nothing is written to it.
- One folder takes new saves ("New saves go here", the first added by default; "Use for new saves" moves it). Removing it passes the mark to the next folder.
- A save or edit writes the item's v2 file to its main copy (oldest-added folder holding it), else to the new-saves folder: `src/lib/folder-write.js` (web, served as `/lib/folder-write.js`) and `Store/FolderWriter.swift` (Mac), checked against the same expected files (`test/fixtures/folder-write.json`, regenerate with `node scripts/make-folder-write-fixtures.mjs`). People and places are matched to the folder's own files or created; images are copied into `media/`. Opening an item never writes.
- Turning writes on never rewrites the folder: the web records each item's fingerprint the first time (a baseline), the Mac notes the time and follows SwiftData history from then on (`Store/FolderWriteObserver.swift`, so edits pulled from the web or another device are written too).
- A file changed outside Stello since Stello last wrote it is merged, never overwritten (tags and links combine, the newer value wins, both notes kept); notes a merge brought in are kept on later writes. A copy that changes in a non-main folder merges into the main copy; a change to the main copy pulls nothing in, so an older copy never undoes a Stello edit.
- Delete moves every copy (and its `media/` files) to its own folder's `.trash/<YYYY-MM-DD>/`; day folders older than 30 days are cleared on the next read.
- Folder item counts leave out people and places that exist only as files (ids `person-…`/`place-…`).
- Not yet: the per-folder ingest choice (Markdown, CSV, PDF, bookmarks, images as items), the shared Apple folder list, Drive/Dropbox on web, deletes made on the web while the web has no folder access are only moved by a device that has one.
