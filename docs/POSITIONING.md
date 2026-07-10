# Stello — Positioning (v2, 2026-07-07)

Owner-confirmed frame: **three core capabilities — Parser · Instrument · Educator — lead everything.**
Decisions locked: built for Arjun + team first → **public v1 launch target: fall 2026** → **subscription**
(maintenance + service are part of the product). Iterating from here.

---

## One-liner candidates (v2, built on the three capabilities)

1. **"Stello doesn't store your references. It understands them, puts them to work, and teaches you what they mean."** — the three pillars in one sentence; long but complete.
2. **"A reference library that thinks."** — short umbrella; each pillar becomes a sub-head.
3. **"Save it once. Stello parses it, connects it, and brings it back when it matters."** — capability arc in user language.

## The problem

Designers save relentlessly and retrieve almost never. Every existing tool optimizes the **save**
(one click, infinite pile) and abandons everything after: the pile doesn't understand itself, can't
be used mid-project, and teaches you nothing. The designer's real reference library stays in their
head, decaying. Stello's bet: a reference is only valuable if the tool does work *on* it — at capture
and forever after.

## The three capabilities

### 1 · PARSER — it understands what you saved
*Not a static drop of files: every item is analyzed, structured, and connected the moment it arrives.*

At capture, Stello classifies what kind of thing this is (a website, a person, a typeface, a foundry,
a place), extracts its structure deterministically (socials, credits, locations — parsed, not
hallucinated), reads it with on-device AI (weighted tags across color/style/mood/format…, quotable
snippets, and *why you probably saved it*), and threads it into everything already in the library —
related items by shared signal, entities cross-linked (a typeface knows its foundry; a website knows
its typography credits).

**Shipped:** deterministic page classification · per-kind typed metadata · on-device enrichment
(tags/snippets/why-saved) · weighted 8-category tags · related-items graph · full-text search over
all of it · review flow (on-card badge + intent facet).
**Next:** kind-dispatched enrichment (per-kind AI jobs) · typed highlights ("saved for *this* scroll
animation, *this* palette") · visual-similarity embeddings.

### 2 · INSTRUMENT — it puts the library to work on the project in front of you
*Saved data becomes decision support: the archive answers questions mid-work instead of waiting to be browsed.*

The library isn't a museum — it's tooling. Filter by intent ("everything saved for
grid-system-reference"). Surface what's relevant to the brief you're working on. Use accumulated
data to make concrete calls: a type scale that fits the active project's font, a palette drawn from
what you actually return to, an export that lands in the deck. Revisit tracking (what you *return to*,
not just what you grabbed) is the signal layer that makes recommendations honest.

**Shipped:** intent facet + filters · search-over-everything · revisit tracking (signal accruing
since Jul 2026) · related-items on open.
**Next:** brief-aware surfacing (paste the project context, get your own archive ranked against it) ·
decision tools per kind (type-scale/pairing from typeface data is the flagship example) · one-click
export to deck/PDF · taste timeline & fading-reference grooming.
**Honesty note:** this is the least-built pillar today — and the one that most differentiates a
*tool* from a *pile*. It should headline the roadmap, not the current-state claims.

### 3 · EDUCATOR — it teaches you about what you saved
*Deterministic extraction plus proactive context: open a typeface and know its designer, foundry,
lineage; open a person and know their work, studio, where they are — connected to the wider world.*

Every typed item carries its own dossier — not AI summary soup but structured facts (a typeface's
designer, foundry, release year, classification; a person's studio, socials, notable work) shown
contextually and proactively where you're already looking. Entities link to each other inside the
library, and outward: Stello connects what you saved with what the internet knows about it, so one
saved specimen becomes a doorway into a lineage, a foundry catalog, a person's whole practice.

**Shipped:** per-kind detail dossiers (typeface/website/individual/studio/foundry sub-cards) ·
entity cross-links (tappable refs when the target exists in the library) · deterministic extraction
at capture.
**Next:** internet-connected enrichment (pull the wider context for an entity, clearly sourced) ·
proactive surfacing ("this designer also made two things you saved in 2024") · zeitgeist detection
("you've saved 14 chromatic-aberration things this quarter — here's the cluster").
**Tension to resolve deliberately:** the educator reaches out to the internet; the trust story is
on-device. The line to hold: *judgment stays on-device (taste, intent, tags); lookups are transparent,
user-visible fetches of public facts.* Say this explicitly in the product and the pitch.

## Supporting pillars (now evidence, not headlines)

- **Private intelligence** — enrichment and taste modeling run on-device (Apple Foundation Models);
  local-first SwiftData + private CloudKit. Feeds trust in all three capabilities.
- **The archive outlives the web** — items keep their images/text locally; link-rot doesn't erase
  the library. (Rendered-page archive still a gap.)
- **It reads your taste back to you** — the instrument pillar's emotional peak: taste timeline,
  annual self-portrait. Every week of revisit data compounds this.

## Audience & go-to-market shape (owner-confirmed)

- **Now → fall:** Arjun + team are user zero — the studio-team use case (shared references *with
  provenance*: who saved it, why they said so) gets proven internally before it's sold.
- **Fall 2026:** public v1 for the target audience — working visual designers who already hoard
  references; typography-serious designers as the sharpest beachhead (no other tool models a foundry).
- **Model: subscription.** The service earns it: sync, model/enrichment updates, internet-connected
  educator lookups, continued parsing improvements on the library you already built. Frame it as
  *the library keeps getting smarter*, never as rent for access to your own files — local-first
  ownership of your data stays the trust floor under the subscription.

## Competitive one-liners (updated to the three capabilities)

| Against | The line |
|---|---|
| **mymind** | mymind stores privately; Stello *parses* — it knows what a foundry is, why you saved that specimen, and what to do with it mid-project. |
| **Are.na** | Are.na is a social practice; Stello is a working instrument. It remembers *why* — which Are.na strips even from teams. |
| **Pinterest/Cosmos** | Their algorithm feeds you everyone's taste; Stello studies yours and puts it to work on your brief. |
| **Raindrop/bookmarks** | Bookmarks store URLs — the least durable part. Stello keeps the reason, the artifact, the structure, and the lesson. |
| **Eagle / DAMs** | Eagle organizes files; Stello understands references — and teaches you about them. |
| **Screenshots folder / Notes** | The honest competitor. Capture is just as fast — but with Stello it comes back out, smarter than it went in. |

## What Stello is NOT

- Not social — no public boards, no follower graph. Team sharing is provenance-rich collaboration, not an audience.
- Not a read-later app; references, not articles-to-finish.
- Not a DAM; project files live elsewhere.
- Not cross-platform-someday: Apple-native is identity (on-device AI + CloudKit + Share Extension *is* the product).

## Proof points ledger (keep honest for any page/pitch)

**Shipped:** capture (URL/paste/drop/Share Ext) · classification + typed entities · on-device
enrichment · intent facet + review badge flow · search-over-everything · weighted tags ·
related items · revisit tracking · per-kind dossiers + cross-links · masonry/weeks/timeline/themes ·
local-first + CloudKit sync.
**In verification:** live on-device AI on real hardware (macOS in progress; iOS pending).
**Committed next:** kind-dispatched enrichment + typed highlights · Supabase→native migration.
**Roadmap:** brief-aware surfacing · decision tools (type scale first) · internet-connected educator ·
taste timeline · vibe search · embeddings · exports · rendered-page archive.

## Remaining open questions for v3

1. **Fall v1 scope line:** which slice of each pillar must be true at launch? (Parser is nearly there;
   instrument needs at least brief-aware surfacing or one decision tool; educator needs the internet
   connection to earn its name. Proposed launch bar: all three pillars demonstrable, one deeply.)
2. **Team features at launch or after?** Shared-with-provenance is the studio wedge but CloudKit
   sharing is real work — v1 or fast-follow?
3. **Typography centrality:** lead the marketing with the type-world depth (beachhead story) or keep
   it as proof of parsing depth? (My lean: lead with it — sharpest possible "this was built for
   people like me" signal, and the educator demos best on a typeface.)
4. **Web app's role in the story:** companion capture surface, quiet legacy, or silence?
5. **Subscription tiers:** one price, or free-local / paid-service split (sync + educator lookups +
   model updates as the paid line)? The split maps suspiciously well onto the local-first architecture.
6. **Name story:** worth one line on the site if it exists.
