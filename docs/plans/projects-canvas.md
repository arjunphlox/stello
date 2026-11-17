# Projects canvas (Nov 2026)

**Why:** the old "Why saved" presets were picked in a hurry at save time, so they only roughly fit. Intent is better captured when an item is used.

**Shape (v2, after Arjun's review of v1):** the board is a mode of the library, not a separate page. Opening a project narrows the library grid to a column on the left; the board fills the rest; the item panel opens to the right without covering cards.

- **Picking from the library:** drag cards straight from the grid (search and filters work as usual), press **+ Add** on a hovered card, or Shift/⌘-click several and press **Add to board**. Cards already on the board fade in the grid.
- **Canvas basics:** pan (scroll, Space-drag, middle button, touch), zoom (pinch, ⌘/Ctrl-scroll, − / + / 0 keys and buttons), Fit (Shift 1), zoom %, minimap (click to jump), marquee and Shift multi-select, move selections, snap to the 24px dot grid (Alt to skip), Delete removes from the board, double-click opens the item panel.
- **Cards:** cover, title, source domain, kind icon, intent line. Zoomed in: tags on the cover. Zoomed out: covers only. Card height never changes with zoom, so layouts stay valid.
- **Arrangement (rules only):** a placed card lands next to its most similar card, and its closest unplaced saves appear around it as faded ghosts (one click keeps one and links it). **Tidy** packs groups and loose cards (linked cards stay together). **Cluster** by topic, kind, source or colour makes labelled groups.
- **Suggested actions (rules only, max two at once, dismissible):** "N share 'tag' → Group them", "X links N items → Arrange around it", "N links say 'label' → Group these", "Related saves → Show around it" (one card selected), "N have no 'what for' → Add reasons" (steps through cards).
- **Intent:** inline one-line field on the card after placing ("What's this here for?"), inline label field on a new link. Enter saves, Esc skips.
- **Export:** Markdown brief (groups, items with links and reasons, named connections).

**Performance:** the board is one GPU layer (translate + scale); only cards in view (+300px) are in the DOM. Similarity is one pass over the library per action, never on open.

**Not yet:** projects live in this browser's localStorage (`stello.projects.v0`); saving to D1 + sync to the Apple apps, "Used in" on the item panel, and turning a group into a real collection tag come next.
