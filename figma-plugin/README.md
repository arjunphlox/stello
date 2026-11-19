# Stello for Figma and FigJam

A development plugin: no build step. `code.js` works on the canvas, `ui.html`
is the panel, and both talk to the Stello Worker.

## Install (Figma desktop app)

1. Plugins → Development → **Import plugin from manifest…** → pick `figma-plugin/manifest.json`.
2. Run **Stello** from Plugins → Development. Press **Connect**. Stello opens with a code; check that it matches, then press **Connect** there.
3. Done. The token stays on this computer (`figma.clientStorage`).

## What it does

| Where | What |
| --- | --- |
| Figma + FigJam | Search your library, click or drag to place a **Stello card**: image, title, kind · source, tags and colours. Shift-click to place several. |
| Figma + FigJam | Each card keeps its Stello slug and source link. Select it to get **Open source** and **Open in Stello** in the properties panel. |
| Figma + FigJam | Select anything to see **related saves**. Stello cards use the Layer 1 rules (same colour, style, idea, place, kind, source); any other selection uses its text and fill colours. |
| Figma + FigJam | **Save selection to Stello** exports frames as PNG and saves them with a link back to the frame. |
| FigJam | **Board sync**: pick the Library canvas or a project. **Lay out** places its groups as sections, its cards, its Layer 2 links as connectors and its notes as stickies. **Sync to Stello** sends the board back: positions, sections → groups, connectors → links (label words pick the kind: influence, contrast, part of, question, maybe), stickies → notes (next to the nearest card, ending in "?" = question). Sections named **Use** or **Rejected** set that state on their cards. |
| FigJam | **Similar lines** draws the Layer 1 links between the cards on the board as dashed connectors. They're a view only and never sync. |

## The Worker side

- `GET /api/library`, `/api/library/search`, `/api/library/related`, `POST /api/library/match`, `POST /api/library/links` (`src/routes/library.js`)
- `/api/projects` (`src/routes/projects.js`, doc shape in `src/lib/projects.js`). `POST /api/projects/:id/board` merges a board.
- Pairing: `/api/pair/*` + `pair.html` (`src/routes/pair.js`). Gives the plugin a device token, the same kind the Apple apps use.
- `/img/<key>?format=figma`: a JPEG copy of up to 1200px, because Figma plugins can't place WebP.

## Stello as an MCP connector (Figma agent, Claude Code, Cursor)

Open `https://stello.arjunphlox.workers.dev/pair.html?new=1` (or **⋯ → Connect an AI agent** in the plugin) and press **Make a token**.

- **Figma agent:** Add context → Connectors → Manage → Created by you → Create. URL `https://stello.arjunphlox.workers.dev/api/mcp`. Under Advanced settings, add the header `Authorization: Bearer <token>`. Custom connectors need a paid Figma plan.
- **Claude Code:** `claude mcp add --transport http stello https://stello.arjunphlox.workers.dev/api/mcp --header "Authorization: Bearer <token>"`

Tools: `search_library`, `get_item`, `related_items`, `list_projects`, `get_project`, plus write tools `add_to_project`, `link_items` and `add_note`. Clients keep write tools off until you turn them on.

## Limits

- Images are placed at up to 1200px wide, to keep files light.
- Sync runs when you press it. Plugins can't run in the background.
- `figma.fileKey`, used for the link back on "Save to Stello", only works while the plugin is a development or private plugin.
