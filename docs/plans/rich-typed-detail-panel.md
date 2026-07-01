# Plan — Rich typed detail panel + Optacos CMS port

Status: **PLAN ONLY** (approved scope this round). Implementation + data import = next round.
Source of truth: Optacos Framer project `YB5gCIPhUzluc6sy8HIM` (read live via `@framer/agent` on 2026-07-01).

## 1. Card types (derived from Optacos CMS collections)

| Stello `kind` | Optacos collection | Count | Notes |
|---|---|---|---|
| `typeface` | Typefaces | 36 | richest; the model case |
| `website` | Websites | 38 | |
| `individual` | Creatives | 47 | people/type designers/founders |
| `studio` | Agency/ Studio | 4 | agencies/studios |
| `foundry` | Type Foundries | 19 | |
| `place` | Geographies | 18 | city + country (mostly a facet of others) |
| `link` (default) | — | — | fallback for everything else already in Stello |

Tag collections (Website Tags 40, Typeface Tags 137, Creative Tags 11, Type Foundry Tags 9) → fold into Stello's existing weighted `Tag` system with a `facet`/`tagFilter` (e.g. "Family Name", "Website Category", "Focus Area", "Distribution Platform", "Profession").

## 2. Stello data-model approach (recommended)

Keep the existing `Item` as the base (title, sourceURL/domain, summary, images, tags, snippets, dates). Add:

- `Item.kind: String` — one of the kinds above (default `link`). Drives which sub-cards render.
- `Item.metadataJSON: String?` — a Codable, per-kind typed payload (decoded into `TypefaceMeta`, `WebsiteMeta`, `IndividualMeta`, `FoundryMeta`, `StudioMeta`). Keeps the schema flexible + CloudKit-friendly (one column, no giant model explosion).
- A lightweight `EntityRef` (name + optional slug + kind) list inside metadata for cross-references (Type Foundry, Type Designer, Founders, Typography used, etc.) — resolve to real `Item`s when both exist, else render as labels/links.
- Reuse `ItemImage` for specimen/gallery images (add an `ItemImage.role` string: cover / specimen-intro / specimen-words / specimen-sentences / graphic / gallery / preview).

> Rationale: per-type SwiftData `@Model`s (×6) would explode the CloudKit schema and complicate sync. A `kind` + typed-JSON facet is the standard local-first pattern and matches how the panel renders (a list of optional sub-cards, each shown only if its data exists).

## 3. Panel shape (applies to Mac panel, iPad panel, iOS sheet)

- Panel = **outline only, no fill** (border + rounded corners; transparent body).
- Content = a **vertical scrollable stack of sub-cards**. Each sub-card focuses on ONE data type; height = its content.
- Each **sub-card** = outlined block, title (caption/label) + its content.
- **Column reflow** by panel width (reuse the existing 1→2 column logic): default **single column**, 2 columns when wide (≥ ~520pt with the wider panel range).
- Order: media/specimen first, then summary, then the type-specific facets, then related + FAQs.
- Only render a sub-card if it has data (avoids empty sections).

## 4. Sub-card catalog

### 4a. Typeface (model case — from the Typefaces collection)

| # | Sub-card | Source fields |
|---|---|---|
| 1 | **Specimen** (image gallery, thumbnails) | Intro 200/120/56/12/P, Words 1–5, Sentences 1–3, Title Large/Medium/Small |
| 2 | **Summary** | Name, Overview, Description, URL, Specimen Link |
| 3 | **Classification** | Classification, Personality (chips) |
| 4 | **Weights** | Weight Count + Weight Types (chips: hairline…black) |
| 5 | **Styles** | Style Count + Style Types (normal/italic…) |
| 6 | **Languages** | Languages Count + Languages Region (latin, cyrillic, arabic…) |
| 7 | **Formats & tech** | Available Formats (otf/ttf/woff/woff2), Variable Font Support, OpenType Features |
| 8 | **Licensing & pricing** | License, Paid/Free, Starting Price, Trial Availability, Student Discount, Distributed On |
| 9 | **Foundry & designer** | Type Foundry (→foundry), Type Designer (→individual), fallback strings |
| 10 | **Technical details** | Release Year, Last Update, Version, Family Count, Family Font Names |
| 11 | **Letterform graphics** | Spacing/Strokes, Rare Letterforms, Weight & Balance, Frequent Letters, Pangram, Balanced Capitals, Ascenders/Descenders |
| 12 | **Insights** | Highlights, Use Case, Design Features |
| 13 | **Related fonts** | Pairing Fonts, Similar Fonts, Fork Fonts, Preview gallery |
| 14 | **FAQs** | Q1–Q12 / A1–A12 (disclosure rows) |
| 15 | **Appears in / by** | Creatives, Websites using this typeface |

### 4b. Website
Cover + Gallery (images) · Summary (Name, Tagline, Description, URL) · Category/Traits/Focus Areas (chips) · Review (formatted) · Tech (Platform, Tech Stack) · People (Founders, Branding by, Site designer/agency, Creatives) · Typography (Typefaces, Foundries, count) · Structure (Web Pages, Key Components + counts) · Timeline (First Published, Date Added/Updated).

### 4c. Individual (Creative)
Identity (Name, Pronouns, Bio, Location) · Professional (Professions, Traits, Experience yrs, Current Role/Employer, Notable Works, Signature Style) · Work & community (Own products, Speaking, Workshops, Community) · Contact/Social (X, Instagram, LinkedIn, Behance, Bluesky, Mastodon, Threads, Blog, Shop) · Personals (Favourite Book, Fun Fact, Hobbies) · Related (Typefaces, Foundries).

### 4d. Studio / Agency
Identity (Name, URL) · Work (websites) · Team (creatives).

### 4e. Type Foundry
Identity (Name, Description, URL, Category) · Origin & team (Geography→place, Founded Year, Founders/Designers) · Pricing & licensing (Price Range, Trial, Student Discount, Licensing Types) · Design approach (Philosophy, Popular Fonts, Specialisation, Custom Services) · Presence (Social, Email, Thoughts) · Distribution · Related (Typefaces, Websites, Creatives).

### 4f. Place (Geography)
City, Country · derived: foundries/creatives based here.

## 5. Import mapping (next round)

- Pull each Optacos collection via `@framer/agent exec` (already validated) → map fields per §4 into `Item(kind:…, metadataJSON:…)` + `ItemImage`(role) + `Tag`(facet).
- Download `framerusercontent.com` image/SVG URLs → store as `ItemImage` bytes (specimen SVGs render crisp; keep as data).
- Resolve references by slug across collections (Type Foundry, Type Designer, Typography, etc.).
- Seed as real Stello items so the rich panel is testable end-to-end (36 typefaces first, then websites/creatives/foundries).
- AFM local model fills gaps (Overview/Highlights/Use Case/Description) where Optacos left them blank.

## 6. Additional sub-card suggestions (for Stello's existing generic/link cards)

Beyond the Optacos types, these sub-cards suit generic saved links/articles/tools already in Stello:
- **Key takeaways** (AFM-summarized bullets) · **TL;DR** one-liner.
- **Quotes / highlights** (saved snippets — already modeled).
- **Reading time / word count / published date / author / publication**.
- **Table of contents** (headings extracted from the page).
- **Color palette** (dominant colors extracted from the cover — Stello already has color tags).
- **Tech/stack chips** for tool/product links.
- **Code snippets** (for dev/GitHub links) · **Repo stats** (stars/forks — already visible on some covers).
- **Related items** (existing shared-tag relatedness) · **Where referenced** (backlinks).
- **Actions** (open, enrich, share, download bundle — already in the context menu).

## 7. Open questions for implementation round
- Confirm the `kind` set + whether `place` is a full card or only a facet.
- Confirm whether to import ALL Optacos collections or typefaces-first.
- Confirm image handling for specimen SVGs (store bytes vs remote URL cache).
