# Library canvas (Nov 2026)

**Why:** the old "Why saved" presets were picked in a hurry at save time, so they only roughly fit. Intent is better captured from use. After two board prototypes (PRs #86, #87), Arjun set the direction on Nov 19 2026. The canvas is the Figma "Exploration canvas" (file bhsqjw3EbQance8tClHfWx, node 13:1783), made interactive. It is a second view of the same library, not a separate board.

**Shape**
- **Switch:** a grid/canvas switch sits right of the search field. Both views show the same items, after search and filters. There are no trays and no split view; the item panel opens as usual (double-click, Enter or Open).
- **Broad groups:** **Group by** Collection (default), Topic, Kind, Colour, Style, Place, Source or Month saved. Each group is a loose masonry block with a title and a "N saves · top tags" line. There are no containers. Cards you drag stay where you put them for that grouping.
- **Cards:** cover with a domain pill, then a details card. The details card holds the title, source · kind · saved date, colour swatches, style, tags, collection, place, why saved and a summary quote. Heights are computed, never measured, so zoom never reflows.
- **Progressive disclosure by zoom:**
  - Far out: colour blocks with large group names. Real cards are used if fewer than about 260 are in view.
  - Middle: cover, title and meta.
  - Close: the full details card.
  - Link labels show close up (from 90%) or for the selected or hovered item. Selecting an item dims the rest and shows up to six of its lines.

**Layer 1: similarity (computed, rules only)**
- The six line types are same place, same colour, looks alike (top colour + top style), same kind, same idea (subject tags) and same style.
- Rare shared features weigh more, and very common ones are skipped.
- Each item shows its two strongest lines (one when far out).
- The **Similarity** menu holds the legend and a toggle for each type.

**Layer 2: intent, time and gaps**
- **Use / Rejected:** marks with an optional reason, set from the selection bar.
- **Influence** (A inspired B, labelled), **Contrast** (vs, labelled), **Part of** a set, and **Question** links (items point to a question).
- **Notes:** double-click empty canvas to add a question, note or set. "Note on image" pins a note to a spot on a cover.
- **Gaps:**
  - When search or filters narrow the view, each group can offer one "maybe related" save from the rest of the library. Accept keeps it next to its anchor; Dismiss hides it.
  - Each group also gets one "empty spot" fact, for example "10 saved, none have a place".
- **Time:** a save timeline below the groups, with the busiest month marked and a taste-drift note (early vs recent tags).
- **Revisits:** glow if opened in the last 14 days, fade if not opened for 120 days or more.
- The **Intent, time & gaps** menu toggles each part.

**Data:** your canvas data is browser-local for now (`stello.canvas.v1`). That covers moved cards, marks, links, notes and dismissed suggestions. It uses the same doc shape as the server projects API being built in a separate thread: `{name, groupBy, cards, links, groups, notes, dismissed}`. Undo is ⌘Z, 50 steps deep.

**Performance:**
- The world is one layer moved with a CSS transform. Only cards in view get DOM nodes (spatial hash).
- Lines and far-out blocks are drawn on one screen-space `<canvas>`.
- Layout reruns only when the result set or grouping changes.
- 10k-item check (headless Chromium, software rendering):
  - Opening the canvas takes about 0.85 s.
  - Render JS per pan frame is 1–4 ms when zoomed in and about 15 ms for the whole-library block view.
