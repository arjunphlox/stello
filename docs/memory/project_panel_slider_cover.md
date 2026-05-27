---
name: Panel image slider — preview vs cover decoupling + dot + icon actions
description: The panel's image slider separates "what's previewed" from "what's the cover" (grid thumb). Reasoning + exact DOM/JS contract for the next time this is touched
type: project
originSessionId: 74a39846-74af-48ec-bd9d-770db4733db6
---
## Shape

Each item panel has one slider: `.panel-image-slider` with `.panel-image-main` (big image + action buttons) + `.panel-image-thumbs` (horizontal strip + upload tile). Designed after user iteration in PR #8.

## Two states, independent

- **Cover** — server truth. Whichever `images[i]` has `is_primary: true`. Mirrored into legacy `og_image_path` for grid card consumption. Stored in slider's `data-cover-path` attribute for client-side lookups.
- **Preview** — client-only. Which thumb is currently shown in `.panel-image-main`. Tracked via the `.is-active` class on thumbs and `data-preview-path` on the main `<img>`.

On first render, preview == cover. Single thumb click swaps preview ONLY. Re-clicking an already-active thumb is a no-op (user explicitly pushed back against the older "second click = set cover" behavior — too easy to trigger accidentally).

## The only paths to change cover

1. **Set-as-cover icon button** (crosshair, top-right of main image). Always visible, even when preview IS cover (harmless no-op in that case — keeps UI consistent). POST `/api/item-update {primary_image_path}`.
2. Programmatic path at capture/enrich time — the server decides based on `is_primary` logic inside `api/item-update.js` or when the first image gets added.

## Action buttons layout

Two 20px circular icon buttons (`.panel-image-action-btn`) at bottom-right of `.panel-image-main`:
- `.js-set-cover` — crosshair icon, accent on hover
- `.js-remove-image` — trash icon, `.is-danger` gives it Radix red `#e5484d`, same-color bg on hover

Both share the translucent-dark `rgba(0,0,0,0.55)` backdrop with `backdrop-filter: blur(6px)`, matching `.card-url-pill`. Native `title` attribute for tooltips.

## Cover indicator dot

`.panel-image-thumb.is-cover::after` pseudo-element — 6×6 pixel dot, bottom-right corner. Color driven by `--dot-color` CSS variable; set in JS based on image luminance (Rec. 601 luma from a 16×16 canvas sample, cached by URL via `_brightnessCache` Map). Falls back to `var(--accent)` when JS hasn't run or image is CORS-tainted.

**No halo / outline on the dot.** The user explicitly vetoed that.

## Upload tile gotcha

The `+` tile uses a `<label>` wrapping a hidden file `<input>` — NOT a `<button>` + programmatic `input.click()`. The button approach was flaky under event delegation (the first upload worked; subsequent uploads after `refreshSliderFrom` re-rendered the tile silently failed because the old input's change listener was gone).

Change listener is bound with **event delegation on `.panel-body`** (not directly on the input), so slider refreshes don't lose it:

```js
bodyEl.addEventListener('change', async (e) => {
  if (!e.target.matches('.panel-image-upload-tile input[type="file"]')) return;
  // … read file, postItemUpdate({manual_image_upload: {base64, mime}})
});
```

## Post-upload UX

After a successful manual upload, the new image is **previewed immediately** (so the user sees what they just added) but is NOT made cover. `captureFlowSlugs.add(path)` isn't relevant here — only `previewThumb(bodyEl, newPath)` is called locally while the server-side is_primary logic keeps the existing cover.

## CSS variables

- `--dot-color` on the cover thumb (inline style, set by JS)
- `--accent`, `--accent-contrast`, `--card-hover`, `--text`, `--text-dim`, `--border`, `--bg-secondary` — all referenced; stay Radix-aligned
- Destructive red hardcoded as `#e5484d` (Radix red-9, matches `.settings-logout`)
