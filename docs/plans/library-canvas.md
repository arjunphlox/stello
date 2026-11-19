# Library canvas (Nov 2026)

**Why:** the old "Why saved" presets were picked in a hurry at save time, so they only roughly fit. Intent is better captured from use. After two board prototypes (PRs #86, #87), Arjun set the direction on Nov 19 2026. The canvas is the Figma "Exploration canvas" (file bhsqjw3EbQance8tClHfWx, node 13:1783), made interactive. It is a second view of the same library, not a separate board.

**Round 3 (Arjun, Nov 19 2026)**
- Camera works like Figma:
  - Two-finger scroll pans. Pinch, Safari gesture events or ⌘/Ctrl + wheel zoom at the pointer.
  - Keys: `+`/`-` step through 2%…200%, `0` sets 100%, Shift+1 fits, Shift+2 zooms to the selection, and the arrow keys pan.
  - Buttons and keys tween the view in rAF, in log space. While the camera moves, only transforms and ink update; card swaps wait until it settles.
- Cards are covers only. The details card opens from the info button beside the source pill and floats over what is below, with no reflow.
- Grid ↔ canvas morph in place: the visible cards fly (FLIP, GPU transforms) from the grid to their canvas spot and back, and the canvas lands framing what you were looking at.
- Packing is skyline (maze-like) for families and for groups.
- Dragging a card close to another shows a dotted rectangle, "Drop to group". Dropping saves it to `doc.groups`, and your groups lead each group.
- No bold titles anywhere in the app (headings 500, group titles 400). The canvas save timeline was removed.
- More than 240 cards in view are painted on the canvas as cover images instead of DOM nodes, with hit-testing kept.

**Shape**
- **Switch:** a grid/canvas switch sits right of the search field. Both views show the same items, after search and filters. There are no trays and no split view; the item panel opens as usual (double-click, Enter or Open).
- **Broad groups:** **Group by** Collection (default), Topic, Kind, Colour, Style, Place, Source or Month saved. Each group has a title and a "N saves · top tags" line. Inside a group, similar items sit together as **families** (up to 12 items) on a soft tint, captioned by what they share ("Typographic · same style · 3"). Items that share nothing strong form a loose block. Cards you drag stay where you put them for that grouping. Drop a card on another family's tint to join it, or clear of its own to leave it.
- **Cards:** cover with a domain pill, then a details card. The details card holds the title, source · kind · saved date, colour swatches, style, tags, collection, place, why saved and a summary quote. Heights are computed, never measured, so zoom never reflows.
- **Progressive disclosure by zoom:**
  - Far out: colour blocks with large group names. Real cards are used if fewer than about 260 are in view.
  - Middle: cover, title and meta.
  - Close: the full details card.
  - **Lines are hidden by default** (Arjun, Nov 19 2026: grouping, spacing, colour and the card itself carry the first level). Hovering a card or note shows its lines. Selecting one dims the rest and shows up to six similarity lines plus your links. Dragging a card shows lines to related items within reach, brighter when they are closer. "Always show lines" in the Similarity menu brings back the old view.
  - Cards with your links show a small count badge.
  - Lines are straight runs with 90° bends and rounded corners. When the two ends are close, a single straight segment is used.

**Layer 1: similarity (computed, rules only)**
- The six line types are same place, same colour, looks alike (top colour + top style), same kind, same idea (subject tags) and same style.
- Rare shared features weigh more, and very common ones are skipped.
- Families come from a greedy cover: the most telling shared feature first (rarer in the library, stronger type, more members).
- The **Similarity** menu holds the legend and a toggle for each type. Turning a type off also re-forms the families.

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
