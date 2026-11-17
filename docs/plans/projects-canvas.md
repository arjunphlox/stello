# Projects canvas (mockup, Nov 2026)

**Why:** the old "Why saved" presets were picked in a hurry at save time, so they only roughly fit. Intent is better captured when an item is actually used.

**What it is:** a board per project. Saving stays one tap; intent is asked later, in context.

- **Suggestions tray** (rules only, no AI): ranks the library by shared heavy tags with what's on the board, same source, same top colour, same kind, and words from the project name. Each row says why ("Shares editorial, elegant"). Search finds anything else.
- **Place** an item (drag from the tray, or +) → one optional question, "What's this here for?". Chips offer this project's recent answers and the item's old preset as a starting point. Enter saves, Esc skips.
- **Link** two items by dragging the dot on a card's edge → optional "How do these connect?" label on the line.
- Click a card to open the usual item panel (it replaces the tray while open).

**Performance:** the board moves as one GPU-composited layer (CSS transform); only cards within the screen + 400px exist in the DOM. Suggestions are one pass over the library per board change, off the open path. WebGL was considered and is kept for a possible whole-library map, not boards.

**Mockup limits:** projects live in this browser's localStorage (`stello.projects.v0`). Not yet: D1 table + sync to the Apple apps, showing "Used in <project>: <note>" on the item panel, zoom, touch drag polish.
