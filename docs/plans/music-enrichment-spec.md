# Music items — kind-dispatched enrichment spec (v1, 2026-07-16)

First concrete slice of the "kind-dispatched enrichment" BACKLOG item, per the decision to
enrich by content type, one type at a time (music → typeface → person → website). Grounded
in a real failure: enriching a Spotify album link produced junk (shell-page instruction text
as snippets, no cover art, irrelevant why-saved) because platform pages are bot-gated app
shells with no prose — generic HTML fetching is structurally the wrong tool for them.

## Ground truth (verified 2026-07-16)

- `open.spotify.com/album/<id>` served to a non-browser client: **6KB stub**, no og:image,
  no JSON-LD. Scraping Spotify is a dead end.
- `https://open.spotify.com/oembed?url=<page-url>`: **open, no auth, no bot-wall** → exact
  `title`, `thumbnail_url` (300×300 album art on Spotify's CDN), embed `iframe_url`,
  `provider_name`. This is the extraction backbone.
- Other platforms: SoundCloud + YouTube have official oEmbed; Bandcamp and Apple Music serve
  real og:/JSON-LD (`MusicAlbum`) to normal fetches. iTunes Search API
  (`itunes.apple.com/search`, open, no auth) resolves artist+album → year, genre, label,
  high-res artwork; MusicBrainz (open, rate-limited) adds tracklists/relationships. These
  open APIs are the educator pillar's first real internet connections.

## Classification (deterministic, capture-time)

`kind = music` when host ∈ {open.spotify.com, music.apple.com, *.bandcamp.com,
soundcloud.com, music.youtube.com} OR og:type ∈ {music.album, music.song, music.playlist}.
Subtype from URL path (album/track/playlist/artist). Zero AI needed.

## MusicMeta (Codable, same pattern as WebsiteMeta etc.)

**Deterministic core (capture, via oEmbed/og):**
- `subtype` (album | track | playlist | artist)
- `title` (cleaned — strip "(Remastered 2004)"-style suffixes into `edition`)
- `artists: [EntityRef]` (links to `individual` items when present in library!)
- `platform` + `canonicalURL` + `embedURL` (the oEmbed iframe — future in-app playback)
- cover art from `thumbnail_url` → stored as the item's real cover (role: cover)

**Open-API layer (educator; capture-time best-effort, refreshable):**
- `releaseYear`, `label`, `genres: [String]`
- `trackList: [{name, duration}]`, `totalDuration`
- `artworkHiRes` (iTunes artwork URL upsized)

**Judgment layer (the only AI involvement):**
- Mood/energy descriptors mapped into the EXISTING mood tag facet (ambient, calm,
  driving, melancholy…) — sourced from genre + description text, not page prose. This is
  the crossover that makes music saves part of the taste graph: mood tags are shared
  vocabulary with visual saves ("calm" links Eno to your muted editorial layouts).
- Vision on the cover art — a sleeve is a design reference in its own right (palette,
  typography, style tags), and for designers that's often *why* the save happened.

**Music-specific why-saved vocabulary** (replaces the generic design suggestions):
`focus-music`, `studio-playlist`, `reference-ambience`, `sleeve-design-reference`,
`artist-reference`, `project-soundtrack`. Never `color-contrast-study` on an album.

## What music items must NOT run

- **No text-extraction / snippets job** — there is no prose; the junk proves it. Skip
  `extractedText` for `kind = music` entirely (also keeps shell-page garbage out of the
  search blob).
- **No generic why-saved prompt** — replaced by the music vocabulary above.

## Pillar fit / sommelier notes

- **Parser:** structured extraction over scraping; artists become EntityRefs in the graph.
- **Instrument:** `embedURL` enables "pour the soundtrack" later (working shelf / play
  while working); served-history ("played during the Acme sprint") pairs music with
  projects the same way references pair with briefs.
- **Educator:** the dossier — artist, year, label, genre lineage ("the 1978 album that
  defined ambient"), cross-links to other saves by the same artist. iTunes/MusicBrainz are
  the first transparent, public-facts internet lookups — exactly the "judgment on-device,
  lookups transparent" line from the positioning doc.

## Sequencing

1. **Music (this spec)** — classifier + MusicMeta + oEmbed capture + cover art + mood
   mapping + panel dossier; suppress text jobs.
2. **Typeface** — richest existing schema (TypefaceMeta), sources: foundry pages, Google
   Fonts (bot-friendly og), MyFonts.
3. **Person/creative** — extends PR #30's IndividualMeta extraction with per-kind AI.
4. **Website-as-reference** — the typed Highlights work (separate design pass, per BACKLOG).
