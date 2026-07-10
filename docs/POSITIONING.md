# Stello — Positioning (draft v1, 2026-07-07)

Working draft for review. Sources: the shipped product (web + native), CLAUDE.md decisions log,
`BOOKMARK_POSSIBILITIES.md`, and the 2026-07 sprint work. Iterate freely — nothing here is precious.

---

## One-liner candidates

1. **"Stello remembers why you saved it."** — leads with the intent-capture differentiator.
2. **"A reference library that reads your taste back to you."** — leads with the self-knowledge arc.
3. **"Your design references, on your devices, with a memory of why."** — leads with local-first + intent.

*(Pick one register: (1) is the sharpest functional hook; (2) is the emotional/aspirational one; (3) tries to do both and is weaker for it.)*

## The problem (as the product actually attacks it)

Designers save relentlessly and retrieve almost never. Every existing tool optimizes the **save**
(one click, infinite pile) and abandons the **return**: you remember a vibe, not a keyword; you saved
the page for one scroll animation, not the whole page; and eight months later the link is dead anyway.
The pile becomes write-only. The designer's actual reference library lives in their head, decaying.

Stello's bet: the moment of saving is the only moment the *reason* exists — so capture the reason,
the structure, and the artifact right then, and every later act of finding becomes cheap.

## Category

Not "bookmarks manager" (Raindrop's word, race to the bottom). Not "moodboard" (Pinterest/Cosmos —
public, algorithmic, near-duplicate). Closest existing label is **"visual knowledge base"** (mymind's
territory), but Stello can plausibly claim a narrower, sharper one:

> **A taste archive for designers.** Personal, private, structured around *why* — with the ambition
> of becoming the instrument a designer uses to see their own taste.

## Who it's for

Primary: working visual designers (brand, product, type-adjacent) who already hoard references —
the person with 40 open tabs, an unsorted screenshots folder, and an Are.na they stopped opening.
The type-specific entity model (typefaces, foundries, studios, individuals) makes **typography-serious
designers** the beachhead persona — no generic tool models a foundry.

Secondary (later, deliberate): small studios needing shared references *with provenance* — who saved
it and why they said they saved it (the thing Are.na deliberately strips).

## Positioning pillars — each one is shipped or in flight, not aspiration

### 1. Intent is a first-class citizen (SHIPPED)
At capture, on-device AI proposes *why you saved this* — kebab-case, craft-specific
(`grid-system-reference`, `empty-state-pattern`) — and accepted reasons become a filter facet.
Recall flips from "what was it called" to "what did I save it *for*." No competitor captures the
reason at ingest; it's the single most defensible product idea in the repo.

### 2. Private intelligence, not cloud intelligence (SHIPPED, verification in progress)
Enrichment — vision tags, snippets, why-saved — runs **on-device via Apple Foundation Models**.
The pitch writes itself against mymind's subscription-cloud AI: *your references, your taste
profile, and your half-formed ideas never leave the machine.* Local-first SwiftData + private
CloudKit; no backend; nothing to breach, nothing to train on.

### 3. Structure no one else has (SHIPPED, capture-side deepening in flight)
Weighted tags across 8 sensory/craft categories (color, style, mood, format…) plus **typed
entities** — a typeface knows its foundry, a website knows its typography credits, a person knows
their studio. That's a design-world knowledge graph, not a folder of cards. Deterministic page
classification at capture (people, foundries) shipped this month; kind-dispatched AI enrichment and
typed *highlights* ("saved for this scroll animation, this palette") are the committed next step.

### 4. The archive outlives the web (SHIPPED in direction, one gap)
Items live locally with their images and text. When Dribbble delists or the portfolio dies, the
reference survives. Full rendered-page archival is the remaining gap; the local-first architecture
makes it a feature, not a rebuild. Against every cloud tool: *their* pile rots twice — once on the
web, once when you cancel the subscription.

### 5. It reads your taste back to you (DATA ACCRUING, views next)
Revisit tracking shipped July 2026 — the archive now knows what you *return to*, not just what you
grabbed. That signal plus weighted tags over time funds the roadmap's emotional peaks: the taste
timeline, "you've saved 14 chromatic-aberration things this quarter," the annual taste self-portrait.
This pillar is the moat-in-waiting: nobody can compete with a year of *your* accumulated signal.

## Competitive one-liners

| Against | The line |
|---|---|
| **mymind** | Same privacy promise, but the AI runs on your device — and Stello knows what a foundry is. Depth over breadth. |
| **Are.na** | Are.na is a social practice; Stello is a private instrument. And Stello remembers *why*, which Are.na strips even from teams. |
| **Pinterest/Cosmos** | Their algorithm feeds you everyone's taste; Stello studies yours. "More like this" that returns adjacent, not duplicate. |
| **Raindrop/bookmarks** | Bookmarks store URLs. Stello stores the reason, the artifact, and the structure — the URL is the least durable part. |
| **Eagle / local asset managers** | Eagle organizes files; Stello understands references — intent, entities, taste over time. |
| **Screenshots folder / Notes** | The honest competitor. Stello's answer: capture is just as fast (Share Extension, paste, drop), but it comes back out. |

## What Stello is NOT (say it out loud)

- Not social, no public boards, no follower graph — deliberately.
- Not a read-later app; it's for *references*, not articles-to-finish.
- Not a DAM/file manager; project files live elsewhere.
- Not cross-platform-someday: Apple-native is the identity (local AI + CloudKit + Share Extension
  *is* the product), not a limitation to apologize for.

## Proof points ledger (for any page/pitch — keep honest)

**Shipped:** capture (URL/paste/drop/Share Ext) · on-device enrichment (tags/snippets/why-saved) ·
intent facet + review flow (on-card badge) · full-text search over everything incl. typed metadata ·
weighted 8-category tags · typed entities + per-kind metadata · deterministic page classification ·
revisit tracking · masonry/weeks/timeline/themes UI · local-first + CloudKit sync.
**In verification:** live on-device AI on real hardware.
**Committed next:** kind-dispatched enrichment + typed highlights · Supabase→native migration.
**Roadmap (designed, unbuilt):** taste timeline · vibe search · brief-aware resurfacing · zeitgeist ·
visual-similarity embeddings · exports (deck/PDF) · rendered-page archive.

## Open questions (answer these to lock v2)

1. **Is Stello a product or an instrument?** Everything above works as positioning for a shipped
   product — but the repo history reads like a personal tool built with product-grade care. Are we
   positioning for the App Store, for a small paid audience, for portfolio/story value, or for you?
   The answer changes tone everywhere (e.g., "the moat" framing only matters if there are competitors
   to moat against).
2. **How central is typography?** The entity model (typefaces/foundries) suggests a type-nerd
   beachhead; the tag system suggests all visual designers. Lead with type-world depth, or keep it
   as supporting proof of "structure no one else has"?
3. **Does the web app have a future in the story?** Currently coexisting, not sunset. If native is
   the identity, the web version needs a role (companion? legacy? capture-anywhere?) or silence.
4. **Price/model instinct, even rough:** one-time purchase reads "instrument you own" (fits pillars
   2/4); subscription reads "service" (fights them). Free-personal changes the audience question.
5. **The name's story:** is there one? (Stella/star? stellar?) A one-line name story is cheap equity
   in a positioning page if it exists.
