# Stello — Blue-Sky Possibilities for Designer Bookmarks

## Status — 2026-07-06 (native-app era)

Written for the web stack; since then the **native Apple app** (`apple/Stello`, SwiftUI iOS/iPadOS/macOS 27, local-first SwiftData + CloudKit, on-device Foundation Models enrichment) shipped its foundations and is now the primary implementation surface for most of this doc. Three facts change the feasibility math:

1. **Local-first flips the cost of Axis 1/3/8.** Pure queries/aggregations over local data (revisit tracking, taste timeline, calendar resurfacing, palette view) need no API/migration/egress — they're SwiftData properties and in-process math.
2. **On-device AI exists but is small and unverified.** `EnrichmentPrompts.swift` already runs vision tags + snippets + why-saved on-device (@Generable, ~3B model, small context window). Everything corpus-scale (vibe search 2.1, zeitgeist 3.3, synthesis 6.2) must be retrieval-then-rerank, and all AI-quality features are **gated on verifying live Apple Intelligence on a real device** (simulator can't — still pending).
3. **The native app has a per-kind metadata schema this doc predates.** `Item.kind` (`typeface|website|individual|studio|foundry|place|link`) + `WebsiteMeta`/`IndividualMeta`/`FoundryMeta`… in `apple/Stello/Stello/Models/CardMetadata.swift` — structured fields for typography credits, socials, founders, location. Populated today only by the Optacos import; capture doesn't classify or fill it yet. Kind-specific capture (typed per-kind enrichment + typed "highlights" — the structured evolution of §2.3) is the planned direction; see `docs/plans/native-quick-wins-sprint.md`.

Per-item status (native): **1.1 why-saved** — SHIPPED (PR #30): accept chips → intent tags @0.9, "Why saved" facet first in the filter sheet. **1.3 revisit tracking** — SHIPPED (PR #30): `lastOpenedAt`/`openCount`, session-debounced, identity-keyed so panel item-swaps count. **1.5 review strip** — SHIPPED (PR #30): needsReview-gated strip above the grid, self-clearing on full review. Plus (beyond this doc): full-text search over snippets/why-saved/per-kind metadata/bodyMarkdown, and deterministic kind classification + social/metadata extraction at capture (`PageClassifier`). **7.1 screenshot-native capture** — image paste/drop/Share-Extension capture shipped; source inference not. **7.3 artifact preservation** — local-first storage + "Download Full Item" zip shipped; rendered-page archive not. Everything else: not started.

Also stale below (kept for the record): web code paths moved `api/*` → `src/routes/*` + `src/lib/*` in the Cloudflare migration, and enrichment now takes **one 1440×900 screenshot**, not three breakpoints (2026-05-20 decision).

## Context

Stello already captures more signal than it surfaces. At ingest it harvests: weighted tags across 8 categories (format, domain, style, subject, tool, location, mood, color), vision-derived palettes, "why saved" reason candidates, snippet candidates, full-page screenshots at 3 breakpoints, and the raw HTML. Per item it also stores `added_at`, `analyzed_at`, `updated_at`, a transient `enrichment_candidates` bag, and a `needs_review` flag. What it does *not* do: track view/revisit behavior, compute cross-project overlaps, reason about time, or do anything with accumulated taste.

The question behind this doc: **once a designer has 200, 2000, 20000 items, what can Stello do that no other tool does?** Below is a wild-but-grounded menu, organized from "tomorrow" to "completely new shape."

---

## Axis 1 — Make the dormant data earn its keep

Stello already captures things it doesn't yet *use*. Easy wins:

### 1.1 Intent-first recall ("why did I save this?")
The "why saved" reasons are collected at capture time (`api/enrich.js:313-398`) and then essentially vanish — users see them once in the capture form and they rarely resurface. Promote `reasons` to a first-class facet alongside tags. Let users filter: "show me everything I saved for *typography-pairing*", "for *grid-system-reference*". This is the single cheapest unlock — the data is already there, just unused.

### 1.2 The taste timeline
`added_at` + weighted tags = a time-series of taste. Render it. "Your 2024 was serif-heavy and muted; your 2025 is sans + saturated." Aggregate color-tag weights by month into a literal palette strip across the year. Designers have never seen this about themselves.

### 1.3 Revisit signal
Schema has no `last_opened_at`, `open_count`, `copied_count`, `exported_count`. Adding these (one migration, tracked via `/api/item-touch`) unlocks every recommendation feature below. Also enables *honest decay*: items untouched for 18 months dim in the grid unless they trend back up in similarity to recent saves.

### 1.4 Co-occurrence map
The related index (`app.js:401-432`) already computes pairwise overlap but only exposes it via one shuffle button. Ship a proper **co-occurrence graph view**: force-directed, nodes are tags, edges are co-save strength. Scrub across time to see clusters form and dissolve. Click a cluster, it becomes a working filter.

### 1.5 Rescue the enrichment suggestions
Candidate images and snippets live in `enrichment_candidates` forever but surface only the first time a panel is opened. A "recently enriched, awaiting review" strip on the home screen would harvest the work the AI already did.

---

## Axis 2 — Make search work how designers *actually* remember

Keyword search fails for designers because they remember vibes, not nouns.

### 2.1 Vibe search
Free-text like *"grainy washed-out serif thing"* or *"early-2000s catalog energy"*. Route to Claude with the item corpus (tags + summaries + why-saved reasons) as context; return a ranked list. Cheap because we only feed the distilled metadata, not every screenshot.

### 2.2 Visual-similarity by embedding
For each `og_image` run a CLIP-style embedding at enrichment time (store a 512-d vector in a new column). Enables:
- "more like this" that returns *adjacent, not duplicate* (explicit diversity penalty)
- cross-media matches — a photograph and an illustration that share composition
- palette-only vs composition-only vs mood-only similarity, as three separate sliders

### 2.3 Sub-element annotation
Designers save an image for one corner of it. Let them draw a box on the detail view and tag *that region* — "this typographic scale", "this specific gradient". Index those crops as their own searchable objects. Existing curation UI in the item panel (`app.js:754-924`) can be extended with a cropper modal.

### 2.4 Temporal phrasing
"What did I save the week we pitched the coffee brand?" The data is there (`added_at`), the parser isn't. Natural-language date scoping on top of existing filters.

---

## Axis 3 — Right-moment resurfacing

The biggest designer complaint: *I save it and never see it again.* Fix it by shifting from "user pulls" to "system pushes — at the right moment."

### 3.1 Brief-aware surfacing
User pastes (or writes) a one-paragraph project brief into a new "current context" box. Stello embeds it, runs similarity against every item's combined metadata, and shows the top 12 in a dedicated strip above the grid. Brief persists per-project and decays. This is the Are.na feature nobody has shipped.

### 3.2 Calendar-anchored resurfacing
"One year ago today you were saving a lot of editorial layouts — here are six you haven't opened since." Quiet, not notification-spammy; lives as a dismissible card at the top of the grid.

### 3.3 Zeitgeist detection
Unsupervised clustering on the rolling 60-day window of saves. When a cluster coheres ("you've saved 14 things with chromatic aberration this quarter"), show it as a generated micro-report: "*Looks like you're into: X. Here's everything that fits, including 4 from 2022.*" Makes visible the patterns the user didn't notice.

### 3.4 Fading reference
Any item untouched for N months with below-threshold tag overlap to recent saves gets a "still relevant?" prompt — archive, keep, or relocate into a dated "older taste" shelf. Honest grooming without manual maintenance.

---

## Axis 4 — Collaboration and taste diffing

### 4.1 Taste diff
Two users (or the same user across two date ranges, or two projects) → render the axes of difference. Not "here are your shared tags" but "*their* palette skews coral/olive, *yours* skews teal/stone; *they* favor editorial grids, *you* favor swiss rationalism." A narrative, not a Venn diagram. Uses existing weighted-tag aggregation.

### 4.2 Shared channels with provenance
If a studio shares a collection, every item carries *who added it* and *why they said they saved it*. Hover an item, see "Maya added this — said 'for the rebrand moodboard'." Are.na deliberately strips this; for working teams it's critical.

### 4.3 Taste invitations
Export a shareable "my taste this quarter" page — small set of items plus a generated paragraph. Follow-able. A soft social layer that isn't Pinterest-style public boards.

---

## Axis 5 — Export to the working surface

A reference that can't leave the tool is half-useful. Every designer-tool loses on the last mile.

### 5.1 One-click deck
Select N items → generate a Figma frame, a Keynote file, or a PDF with titles + source credits + why-saved annotation. The snippet/why-saved data makes captions write themselves.

### 5.2 Narrated walk
An ordered, commented sequence through references — a "walk". New data shape: a lightweight playlist of item IDs + per-item user note + optional audio. Shareable as a public URL. Sits between a Twitter thread and a Pinterest board; no tool owns this.

### 5.3 Print artifacts
Generate a print-ready zine PDF of the year's saves, grouped by a tag or cluster. Quarterly ritual: ship yourself a physical zine. Low-cost magic that no competitor touches.

### 5.4 Brief-to-moodboard
Given the current-context brief (3.1) plus a target format ("12-image moodboard, 16:9, 3×4 grid"), generate a ready-to-send moodboard. The last mile of the most common designer task.

---

## Axis 6 — Counterfactual and generative

This is where it stops looking like a bookmark tool.

### 6.1 Adjacent-tag walks
"What would I have saved if I'd been interested in *brutalism* instead of *minimalism*?" Slide a filter over your own filter bubble; show the shape of the taste you *didn't* develop. Educational, a little unsettling, very designer.

### 6.2 Synthesis pass
Point Stello at a cluster — "my 23 items tagged *grid*" — and ask for a synthesis: *what do these have in common, what are the axes of variation, what's the outlier?* Output is a readable analysis, not a tag cloud. The rich metadata makes this tractable without feeding raw images to a giant model.

### 6.3 Taste self-portrait
Annual artifact: a generated page that summarizes your year in references. Palette strips, mood arcs, format shifts, "most-saved creators", "biggest new interest", "tag you abandoned". Designers are self-obsessed in the best way — this ships itself.

### 6.4 Generative gap-filling
For a cluster of saves, generate a *hypothetical adjacent reference* as an image (SDXL/Flux) — "given your taste in editorial layouts, here's one that would fit." Starting point, not endpoint. Controversial for design culture, hence optional and clearly labeled.

---

## Axis 7 — Capture that doesn't feel like capture

The save step is where momentum dies.

### 7.1 Screenshot-native capture
Paste a raw screenshot (no URL) and Stello runs vision + reverse-image-search to infer source. Most designer saves today *are* screenshots with no URL; current Stello hard-depends on a URL (`api/capture.js`).

### 7.2 Ambient email/Slack/browser capture
An email address that turns forwarded newsletters into items; a Slack bot that captures pasted links from a #inspiration channel; a browser extension beyond the bookmarklet. Capture friction → zero.

### 7.3 Artifact preservation
At capture time, the full HTML is already stored. Go further: archive a rendered snapshot (the screenshots at 3 breakpoints are already being taken — `api/enrich.js`). When Dribbble delists the shot, Stello still has the artifact. This is a **moat**: every other tool loses content as the web rots.

---

## Axis 8 — Shape-shifting views

The masonry grid is one shape. The data supports more.

### 8.1 Map view
Items with a `location` tag plotted geographically. "Everything Japanese I've saved." Cheap — location tags already exist.

### 8.2 Palette view
Rearrange the grid by dominant color along a spectrum. Horizontal scroll from warm to cool. The vision pipeline already produces per-item palette weights.

### 8.3 Timeline / ribbon view
Horizontal strip, week-bucketed, cards scaled by revisit count (once 1.3 ships). Immediate answer to "what was I into in April?"

### 8.4 Tag-graph view
Force-directed map of tags, from 1.4. Doubles as navigation and as a portrait of your taste.

### 8.5 "One-at-a-time" review mode
Full-screen one item, keyboard hjkl to navigate, instant tag/reason edits. Mymind-style meditative review — the opposite of firehose grid browsing.

---

## Axis 9 — What the sommelier frame reveals (added 2026-07-07)

Derived from the positioning work (`docs/POSITIONING.md`, "trusted selector" personification): walking
Stello through what a working sommelier/selector actually *does*, behavior by behavior, and keeping
only what no axis above or BACKLOG item covers. Four consequential, eight supporting.

### 9.1 Multiple palates — my taste vs. the client's (structural, do early)
A sommelier never confuses their palate with the guest's. Stello has exactly one taste model: every
save feeds the same aggregation. Agency reality breaks this — a week of pastel-corporate saves *for
a client's brand world* pollutes your taste timeline and future self-portrait. Fix: project/client-
scoped palates + "guest references" (corkage — items scoped to one project that never count toward
the personal profile). Also quietly the best team feature (studio project-palette vs. each member's
own). Retrofitting gets more expensive every month of accumulated data.

### 9.2 The committed pick + rationale-always (service posture, constrains all Instrument features)
Every planned surfacing returns a set (top-12 strip, cluster, grid). The sommelier's defining act is
committing to ONE bottle with a stated reason. Stello has the data ("this one — returned to 4×, and
the brief reads editorial like your saved reason"). Deeper: **every recommendation carries its
reason, always** — the humility rule made mechanical (a stated rationale can be judged and overruled)
and a real differentiator vs. black-box feeds. Candidate for a standalone service-conduct spec
before fall (one pick · stated reason · prepared for use · defers to your palate).

### 9.3 Served history — usage provenance (cellar book)
Revisit tracking knows what you looked at; the cellar book knows what was *poured, when, for whom*.
Record "served" events (project + date, hooked on export/copy/use actions) → most-served references,
"served 3×, retire?", per-project provenance for teams, and the data feeding 9.1.

### 9.4 Decanting — serve references in usable form
Plans stop at showing the card. A served reference should arrive prepared: palette swatches ready to
copy, identified font names, the highlight crop, the why-saved caption. Distinct from exports (5.1,
end-of-research); this is at-the-moment-of-serving. The difference between a bookmark and an
instrument.

### 9.5–9.12 Supporting
- **9.5 Tasting flights** — ritualized comparative viewing with a question attached: verticals (one
  foundry/designer across your saves) and horizontals (project-priming set before starting).
- **9.6 Drink-now vs. cellar** — aging by *nature*, not neglect: trend-bound vs. timeless saves;
  changes recommendation copy ("use before everyone does" vs. "permanent library"). Complements 3.4.
- **9.7 The working shelf** — by-the-glass list: a deliberately SMALL rotating "drawing from this
  week" surface (revisits + active brief), menu-bar/widget candidate. All planned surfaces are
  archive-sized.
- **9.8 Taste vocabulary teaching** — the educator names your taste in words ("this is
  'neo-grotesque'; you own twelve"); micro-glossary generated from your own corpus.
- **9.9 Spaced repetition for taste** — blind-tasting mode: the archive quizzes you on itself (crop →
  whose work? saved why?). Retrieval practice is how references move into a designer's head; nobody
  has treated a library as something you train on.
- **9.10 Collection gap analysis** — the somm buys for gaps: "deep on editorial, thin on motion —
  and your pitches trend motion." Everything else analyzes what's there; this advises what's missing.
- **9.11 Taste-stretching service** — "you always order the same thing; try this": occasional
  off-center pour from your own never-revisited saves. 6.1 is a view you drive; this is served.
- **9.12 Capture-time commentary** — intake tasting: "unusual for you — first brutalist-pastel in
  your library." Enrichment describes the item; this describes the item *relative to you*.

## High-value highlights across all axes

Picked on *behavioral impact* — how much each one changes the way a designer actually uses their own bookmarks — not on implementation size. Small-but-transformative features are called out alongside bigger ones.

### Tier A — Changes the fundamental loop

**"Why saved" as a first-class facet** *(Axis 1.1, small)*
The single highest ROI move. The data is already captured and then thrown on the floor. Letting a user filter "show me everything I saved for *typography-pairing*" flips the whole recall model from keyword-based to intent-based. A designer stops asking "what was that thing called" and starts asking "what did I save *for*." No other tool in the category offers this because no other tool captures the reason at ingest. Ship cost: a filter drawer entry and a query. Behavioral payoff: outsized.

**Brief-aware surfacing** *(Axis 3.1, medium)*
Fixes the save-and-forget graveyard — the #1 complaint across every tool. A paragraph of "what I'm working on right now" becomes a query that ranks your own archive against the moment you're in. Bookmarks flip from a write-only pile to a pull-request the system services. This is the feature designers describe wanting when they describe Are.na's failure mode.

**Revisit tracking** *(Axis 1.3, small)*
A tiny schema change — `last_opened_at`, `open_count`, `exported_count`, `copied_count` — that is the pre-requisite for nearly everything worth doing. Without it, recommendations are blind, fading-references don't fade, zeitgeist detection has no signal of what *mattered*, and taste timelines can't distinguish "saved and loved" from "saved and forgot." Cheap to add, compounds forever.

### Tier B — Changes how people search and find

**Vibe search** *(Axis 2.1, medium)*
Keyword search is mismatched to how designers remember — they remember moods, not nouns. Free-text queries like "grainy washed-out serif thing" are the natural voice of the user and the only way to hit the long tail of saves. Routing to Claude with distilled metadata (not raw images) keeps it cheap. This single feature makes a 2000-item archive feel 10× smaller.

**Visual-similarity embeddings with diversity penalty** *(Axis 2.2, medium)*
"More like this but different" is the unsolved problem of every reference tool. Pinterest's version returns near-duplicates; that's the opposite of what a designer wants in exploration mode. A deliberately diversity-weighted similarity (same mood, different medium; same structure, different era) is directly useful for moodboarding, pitching, and trend-spotting — the three actual jobs.

**Sub-element annotation** *(Axis 2.3, medium)*
Designers save an image for *one corner* of it — a kerning choice, a curve, a gradient. The whole-image model every tool uses discards the reason. Letting users box a region and tag *that* turns saves into a sub-element library, which is what designers implicitly keep in their heads.

### Tier C — Changes what the tool is *for*

**Taste timeline** *(Axis 1.2, small-to-medium)*
Turns Stello from a storage tool into a *self-knowledge* tool. Rendering your palette, your mood distribution, your format mix as a strip across time answers a question designers have had about themselves forever and never had an artifact for. The annual self-portrait (6.3) is its shareable, viral extension.

**Zeitgeist detection** *(Axis 3.3, medium)*
"You've saved 14 things with chromatic aberration in 3 months — here's the cluster, including 4 from 2022 you'd forgotten." Makes unconscious patterns conscious. This is the moment a designer realizes the tool is reading them back to themselves, not just holding things.

**Taste diff** *(Axis 4.1, medium)*
Comparing two users, or two time periods of the same user, as *axes of difference* ("their palette skews coral, yours skews teal; their formats editorial, yours swiss") is a shape no competitor has. Valuable solo (for retrospectives and case studies), critical in studio teams (to make "whose taste is this" legible).

### Tier D — Changes what the tool *produces*

**Narrated walks** *(Axis 5.2, medium)*
An ordered, commented sequence through references — between a Twitter thread and a Pinterest board. Teaching, pitching, critique, and portfolio retrospectives all want this shape, and no tool owns it. Every designer has sent a screen-record of them scrolling through Figma/Are.na talking over it; this is that, shareable.

**One-click export to Figma/Keynote/PDF** *(Axis 5.1, medium)*
The last mile every reference tool fails at. Captions write themselves from the why-saved field that already exists. The difference between "research" and "delivered deck" is this export, and making it a button instead of a 20-minute copy/paste job is what closes the work loop.

### Tier E — Quiet moats

**Artifact preservation** *(Axis 7.3, small extension)*
Stello already grabs HTML and 3-breakpoint screenshots at enrichment. Committing to them as a durable archive — so when Dribbble delists or Tumblr dies, the reference survives — is an invisible feature that becomes the reason to switch *to* Stello from every other tool as the web rots.

**Screenshot-native capture** *(Axis 7.1, medium)*
Most designer saves today are screenshots without a URL. Paste-an-image → vision + reverse-image-search to infer source. Unlocks the single largest pool of saves currently going into Apple Notes and iMessage-to-self.

**Recently enriched strip** *(Axis 1.5, tiny)*
AI candidates for images/snippets/reasons currently surface *once* at capture and then vanish. A 4-card strip on the home screen for "items awaiting your 10-second review" recovers work the system already did. Zero-cost UX change, visibly increases curation volume.

---

### Why these and not others

Features like map-view (8.1), generative gap-filling (6.4), and print artifacts (5.3) are *delightful* but not load-bearing for how people use bookmarks day-to-day. They belong on the roadmap but not in a "high-value" list — they make fans, not converts.

The highlighted set above all share one property: **each one makes at least one mental motion that designers currently perform in their heads or on paper disappear into the tool.** That's the test. Forgetting why you saved something → gone. Not finding the vibe you remember → gone. Not seeing your own patterns → gone. Not being able to get the references out cleanly → gone.

---

## The recommended first three

If one has to ship progressively, the highest-leverage sequence is:

1. **Promote "why saved" to a first-class facet** (Axis 1.1) — the data is there, the UX change is small, the unlock is emotional: users finally re-find things by intent.
2. **Revisit tracking + brief-aware surfacing** (Axis 1.3 + 3.1) — adds the behavioral signal every later feature depends on, and ships the most loudly-missing designer feature in one motion.
3. **Taste timeline** (Axis 1.2) — becomes the shareable artifact that explains what Stello *is* to other designers. The annual taste self-portrait (6.3) is a natural follow-up.

Everything else fans out from these three.

---

## Critical files (for when any of this becomes a real plan)

Native app (primary surface now):
- Schema / models to extend: `apple/Stello/Stello/Models/Item.swift`, `Tag.swift`, `CardMetadata.swift` (per-kind metadata)
- On-device enrichment (extendable to new @Generable jobs): `apple/Stello/Stello/Capture/EnrichmentPrompts.swift`, `EnrichmentService.swift`
- Capture pipeline (kind classification, deterministic extraction): `apple/Stello/Stello/Capture/CaptureService.swift`, `RuleTagger.swift`
- Search / filters (extend for facets, vibe search recall): `apple/Stello/Stello/Store/ItemFilter.swift`, `Views/TagFilterSheet.swift`
- Detail/review UI (chips, highlights, review strip): `apple/Stello/Stello/Views/CardSubcards.swift`, `SidePanelContent.swift`, `MasonryGridView.swift`
- Constants source of truth: `apple/BUILD_SPEC.md`

Web app (post-Cloudflare-migration paths; the `api/*` refs above are historical):
- Schema / columns to add: `scripts/schema.sql`
- Tag generation: `src/lib/supabase.js`, enrichment: `src/routes/enrich.js`
- Related-items graph: `app.js` (`relatedIndex`); panel curation: `app.js` + `src/routes/item-update.js`; filter drawer: `app.js`

## Verification (when any one of these lands)

- Local: `npm run dev`, capture a URL, confirm the new facet/column/view renders.
- Schema changes: `node scripts/verify-supabase.js` to check RLS + columns.
- Backup round-trip: `node scripts/sync-local.js` still mirrors cleanly.
- Visual QA the new view in Chrome + Firefox (cross-doc VT matters for 8.3 and 8.4).
