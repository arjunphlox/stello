# Moodboards from Safari (Nov 28 2026)

Save links and pictures from any page in Safari, on their own or straight onto a canvas.

## Ways in
| Where | How |
|---|---|
| Mac Safari | Right-click a link, picture, selection or the page: Stello › Save to Stello / Add to <canvas> / Add to a new canvas. A selection saves every link in it. |
| Mac + iPad Safari | Start dragging a link or picture: a drop shelf slides in at the right edge (Save to Stello, up to 5 canvases, New canvas named after the page). Also shows for links dragged in from another window. |
| Toolbar popup (Mac, iPad, iPhone) | This page or All N tabs → Save to Stello, a canvas, or a named new canvas. Rows also take dropped links. |
| iPhone/iPad share sheet | After saving a link, an "Add to a canvas" row (one tap), or Done. |
| Stello canvas (web, Mac, iPad) | Drop links or pictures from Safari or another app on the canvas: saved, then placed where dropped. |

## How it works
- The extension never writes the folders. Each save is one JSON request in the App Group (`SafariInbox/`, `StelloSafari/SafariSaveInbox.swift`).
- The app (`Stello/Store/SafariInbox.swift`) saves each address through the normal capture path (so folder writes, web copy and enrichment are unchanged), places the batch with `CanvasStore.place` (to the right of what's there, up to 4 columns, one group named after the page when 2+), then deletes the request.
- Mac: the extension pokes the running app over its message port, or opens it in the background. iPhone/iPad: the app saves them next time it opens; Safari says so.
- The app shares its canvas list (open one first) in the App Group defaults; Safari puts canvases you used from Safari lately first.
- Batches of more than 5 are not enriched at once; they're enriched when opened.

## Not yet
- The "Folder test" link in the popup belongs to the Safari folder test and goes before release.
- iPhone/iPad Safari has no right-click menu for extensions; use the share sheet or popup.
