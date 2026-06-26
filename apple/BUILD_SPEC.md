# Stello Build Spec Sheet

Exact constants/rules extracted from the Stello web codebase — the source of truth for the Swift port. All values are literal from the web app. Cite this in build prompts so agents don't reinvent.

---

## 1. Tag generation

Pipeline `generateTagsFromMetadata` (`src/lib/supabase.js:240`):
- Format tag (1) via `formatTagFor`.
- Domain tag (1): `{ tag: hostname sans "www.", category: "domain", weight: 0.6 }`.
- Title subject mining: up to **5**, `minLen 3`, weight `0.8` step `-0.1` floor `0.5`.
- Description subject mining: up to **3**, `minLen 4`, weight `0.5` flat, floor `0.5`.
- Rule enrichment (tool/style/mood/location).
- Final: sort by weight desc, **cap 12**.
- Subject weight = `max(floor, start - index*step)` rounded to 2dp. Word pattern `[a-zA-Z]{minLen,}`, lowercased.

Format tag (`enrich-rules.js:416`): no URL -> `{text-note, format, 0.4}`; known host -> `{mapped, format, 0.5}`; else `{website, format, 0.4}`. Lookup key = `domain.replace(/^www\./,'')`.

Rule weights: tool `0.7`, style `0.65`, mood `0.55`, location(text) `0.6`, location(TLD) `0.3`. Matcher `\bpattern\b` case-insensitive.

FORMAT_MAP (host -> tag): instagram.com->instagram, x.com/twitter.com->tweet, pinterest.com->pinterest, behance.net->behance, dribbble.com->dribbble, youtube.com/youtu.be->youtube, vimeo.com->vimeo, codepen.io->codepen, codesandbox.io->codesandbox, github.com->github, medium.com/substack.com->article, figma.com->figma, tiktok.com->tiktok, linkedin.com->linkedin, reddit.com->reddit, producthunt.com->producthunt, awwwards.com->awwwards, are.na->arena, notion.so/notion.site->notion.

TOOL_RULES, STYLE_RULES, MOOD_RULES, LOCATION_RULES, TLD_LOCATION: see `src/lib/enrich-rules.js:40-296` for the full literal tables (figma, framer, webflow, sketch, illustrator, photoshop, after-effects, blender, midjourney, react, swift, swiftui, visionos, etc.; minimalist/brutalist/editorial/...; dark/vibrant/calm/...; tokyo->japan, london->uk, .jp->japan, etc.). Port verbatim.

## 2. Related-items rule (`app.js:578`)
Item B related to A iff BOTH:
- share >=1 tag in category **format OR domain**, AND
- share **>= 3** tags with **weight >= 0.5** (any category).
Self-excluded. Overlap counted only among candidates passing the category gate.

## 3. Masonry / grid (`app.js:820`)
Columns by container width: `<=500 -> 2`, `<=768 -> 3`, `<=1200 -> 4`, else `5`. Fallback 5.
Shortest-column packing by estimated height:
- `COL_WIDTH_ESTIMATE = 250`px.
- image height = `250 * (h/w)`; if has_image no dims -> `250 * 630/1200`; text/placeholder -> `242`px.
Text card shows when `!hasImage && summary.length > 30 && !summary.startsWith('Saved from')`; word cap 200.
Placeholder hues: `[18,80,38,140,25,45,12,100]`.

## 4. Week grouping (`app.js:725`)
ISO week (UTC, Thursday-anchored). Key `YYYY-Wnn` (e.g. `2026-W16`), invalid/missing -> `undated`.
Grid header label `Week N — Month` (e.g. `Week 16 — June`); fallback `Undated`.
Panel footer label `Wnn YYYY` (e.g. `W16 2026`).
Sort items newest-first by `added_at` desc; first week auto-expanded, older collapsed.

## 5. Theme tokens
Modes light/dark; accents lime / **amber (default)** / iris. Default `{ mode: dark, accent: amber }`.
Semantic per accent: `--accent = {accent}-9`, `--accent-hover = -10`, `--accent-subtle = -a3`.
`--accent-contrast`: lime `#37401c`, amber `#4f3422`, iris `#fff`.
Swatch preview: lime `#bdee63`, amber `#ffc53d`, iris `#5b5bd6`.

Radix scales (key step-9 = accent): lime-9 `#bdee63`, amber-9 `#ffc53d`, iris-9 `#5b5bd6` (same both modes).
Full Sand/Lime/Amber/Iris 1-12 + a3 hex values per mode are in `theme.css:9-68` — port both light and dark palettes.

## 6. Capture rules (`app.js:1994`, `capture.js`)
Paste classification priority (skip if focus in INPUT/TEXTAREA or a tool panel is open):
1. clipboard image file (`type startsWith image/`) -> capture image.
2. URL match `/https?:\/\/[^\s<>"']+/g` -> 1 URL capture, multiple -> bulk.
3. trimmed text **length > 5** -> capture text.
Text capture: title = first 5 words; summary = first 200 chars.
Image upload: title `Image upload — {date}`, tag `{image-upload, format, 0.4}`.
Initial `enrichment_status` on all captures: `text_done`.

enrichment_status enum: `pending | text_done | vision_done | candidates_done | error`.
Transitions: capture->text_done; vision ok->vision_done, fail->error; candidates -> candidates_done (or text_done if a cover was promoted, vision pending); pending+enrich(no html)->vision_done; backfill gives up on error/vision_done/candidates_done.
Client poll: every 3000ms, max 14 attempts; stop at candidates_done/error/timeout.

## 7. Card render signature (`app.js:1013`)
djb2 hash (base-36) of `|`-joined: image_path (if has_image), image_width, image_height, title, domain, summary[:200] (only if no image), dominantColor (highest-weight color tag hex, default `#ffffff`). Excludes index/placeholder hue. Used to skip DOM re-render when unchanged.

## 8. Image / enrichment constants
WebP: format `image/webp`, quality **82**, anim true, ingest maxWidth **2400**px, min downloaded image **500** bytes.
Timeouts: **15000ms** for image download, OG fetch, page fetch.
HTML caps: OG **50,000** bytes; enrich page **500,000** bytes; page text to model `.slice(0,6000)`; min text for candidates `> 200`.
Candidate harvest: scan up to **20** `<img>`, store up to **5**, min **100x100**px, alt label max 80; exclude regex `/(\bicon\b|\bavatar\b|\bpixel\b|\btracking\b|\bsprite\b|\bbadge\b|\bfavicon\b|\blogo-?small\b|1x1|spacer)/i`.
Snippets: cap 5, <=400 chars (prompt asks <=200). Reasons: cap 3, kebab-case.
Vision model (web): `claude-sonnet-4-6`; vision categories = **color, style, mood**; context tags <=6 from domain+subject; max_tokens 300 tags / 50 title / 600 candidates; image max 20MB.

> Native note: vision/tagging move to on-device Apple Foundation Models (AFM 3) with `@Generable` typed output; keep the rule tables above as the offline fallback and as the deterministic baseline tests.

---

### Quick reference
- Tag cap 12 · related >=3 @ >=0.5 + format/domain gate · grid 2/3/4/5 @ 500/768/1200 · col estimate 250px · text card 242px
- Week key `YYYY-Wnn` · header `Week N — Month` · paste text min 6 chars · title = first 5 words · summary 200
- WebP q82 / maxW 2400 · timeouts 15000ms · OG 50KB / enrich 500KB · candidates 5 · default theme `{dark, amber}`
