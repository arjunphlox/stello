# Web vs Apple parity pass (Nov 22 2026)

Every screen compared on desktop/Mac, iPad and iPhone; 21 gaps closed on both sides.
Screenshots and the full gap table: https://claude.ai/artifact/STJBG9ZMufg2sEUnAmv3ZX

- Spacing: edge gutter 24 / 16 / 12 (above 768 / above 500 / phone), card gap 24, or 12 at 768 and below, on both apps (Arjun's pick). Apple: `StelloLayout.applyWidth(_:)`.
- Bottom bar: three-line filter icon, "Search" placeholder.
- Detail: title 17; no "Images" label over the iPhone cover. Apple records a cover's pixel size the first time it decodes.
- Filters: title "Filters"; tag search, then Needs review (Available offline is web-only); singular group names; right chevron that turns down; round checks; count = number of tags.
- Panels: round close button on web. Settings: title "Settings", rows in cards on web, Grid row on the Mac panel, Apple "Old web library" import removed.
- Canvas: Apple gains the Similarity and "Intent, time & gaps" menus (saved in `stello.canvas.layers`) and Fit. Web canvas view drops search and filter (they act on the grid; Split keeps them). iPhone bar: name and share on both.
- Split view: dot on grid cards already on the canvas, on Apple too.
- Not on Apple yet: canvas gaps and the revisit glow.
