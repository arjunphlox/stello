# Music items — kind-dispatched enrichment spec (v1, 2026-07-16)

First concrete slice of the "kind-dispatched enrichment" BACKLOG item, per the decision to
enrich by content type, one type at a time (music → typeface → person → website). Grounded
in a real failure: enriching a Spotify album link produced junk (shell-page instruction text
as snippets, no cover art, irrelevant why-saved) because platform pages are bot-gated app
shells with no prose — generic HTML fetching is structurally the wrong tool for them.

## Ground truth (verified 2026-07-16 against 10 real links: Spotify album, Apple Music
## playlist/track×2/artist, youtu.be ×3, music.youtube ×2)

**Platform extraction matrix:**

| Platform | Direct page fetch | oEmbed | What each yields |
|---|---|---|---|
| **Apple Music** | ✅ full page, bot-friendly | n/a | `og:type` gives exact subtype (`music.playlist`/`music.song`/`music.musician`); 1200×630 artwork; JSON-LD: `MusicAlbum`, `MusicComposition` (composer), `MusicGroup` (artist), `MusicRecording`s (artist pages), `AudioObject` (30s preview URLs). Playlist pages carry curator ("Focus Zone **by Arjun Phlox**"). Track URLs encode album+track ids (`/album/<id>?i=<trackId>`). Region in path (`/in/`). |
| **Spotify** | ❌ 6KB bot-gated stub | ✅ open | title, 300×300 art, embed iframe. Nothing deeper without the credentialed API — cross-look up via iTunes Search instead. |
| **YouTube / YT Music** | ⚠️ unreliable for non-browser clients (consent/shell variants, no og) | ✅ open, covers music.youtube URLs too | title, channel (`author_name`), 480×360 thumb (`maxresdefault.jpg` predictable at `i.ytimg.com/vi/<id>/maxresdefault.jpg`), embed. YT Music artist = channel minus `" - Topic"` suffix (auto-generated artist channels). |

**Second-wave probe (2026-07-16, scouted: Bandcamp, SoundCloud, Deezer, Tidal, Mixcloud,
Amazon Music, Last.fm):**

| Platform | Verdict |
|---|---|
| **Deezer** | ⭐ Best-in-class: full page fetch works (`og:type music.album`, 500px cover) AND a completely open JSON API (`api.deezer.com/album/<id>`, `/search?q=` — no auth) returning **UPC**, genres, tracklist, release date, artist, cover sizes. |
| **Tidal** | Official oEmbed (`oembed.tidal.com/?url=`) works → embed + metadata. Embed-tier support. |
| **Mixcloud** | Official oEmbed works fully (title, author, 600px image) — covers DJ mixes/radio shows, a distinct designer-relevant save type. |
| **Bandcamp** | Bot-gated from datacenter IPs; known to serve rich og + JSON-LD `MusicAlbum` to residential/browser clients — expect the app's on-device fetch to work; verify on-device before promising. |
| **SoundCloud** | Official oEmbed documented; probe from datacenter inconclusive — verify on-device. |
| **Amazon Music** | ❌ Bot-walled shell (11KB), no open oEmbed → stays plain `link`, out of scope. |
| **Last.fm** | Not a save target (og:type `website`, noisy titles); its API needs a key. Skip as platform; optional future resolver. |

**Backbone rule (updated):** direct fetch + JSON-LD for Apple Music and Deezer; oEmbed for
Spotify/YouTube/Tidal/Mixcloud (+ SoundCloud/Bandcamp pending on-device verification).
**Cross-platform resolver: Deezer's open API first** (one call yields UPC — a true
cross-platform album identifier — plus genres/tracklist/release date), iTunes Search as
fallback; MusicBrainz later for deep relationships. A UPC on the item means the same album
saved from Spotify and Apple Music can be recognized as ONE work — entity resolution across
platforms, which no platform will ever do for you.

**The YouTube title problem — first legitimate kind-dispatched text-AI job:** raw titles are
packed compounds: "Zara Larsson - How Deep Is Your Love (Calvin Harris, Disciples Cover)
(Live) | Spotify Live Room", "Thassadiya - Video Song | Maa Inti Bangaaram | Samantha |
Chinmayi | … | Santhosh Narayanan" (Indian film-music grammar: song | film | cast | singers |
composer). Deterministic splitting gets ~70%; a small on-device @Generable job (raw title +
channel → {artist, track, version/live/cover, film?}) normalizes the rest. This — not prose
snippets — is what text AI is FOR on music items.

**Classification nuance:** `music.youtube.com` → music, always. Plain `youtube.com`/
`youtu.be` is music only on deterministic signals (channel ends `" - Topic"` or `"VEVO"`,
title contains "Official Music Video"/"Video Song"/"Official Audio", `og:video:tag` music
markers when the page cooperates); otherwise stay `link` — conservative, per the classifier
rule.

**Playlists are palate artifacts:** a saved playlist ("Focus Zone by Arjun Phlox" — the
user's own) carries curator identity; own-playlists are first-party taste signal (ties to
Axis 9.1 multiple-palates) and deserve `curator: EntityRef` + `isOwnPlaylist`.

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

## Where the extraction line is drawn (the 70–80% principle)

Stello is not a mirror of the platform page — the link exists for deep-dive; Stello holds the
*vetted, connected* layer the web can't aggregate. In scope: identity (title/artist/subtype/
edition), artwork, year, genre, label, duration, tracklist (albums), curator (playlists),
film/context (film-music grammar), preview/embed URLs, mood mapping into the shared tag
facet, artist EntityRefs. **Out of scope, deliberately:** play counts, comments, likes,
lyrics (rights + bulk), the artist's full catalog, pricing/offers, recommendations, video
files — that's the platform's live layer, one click away. The test for any field: does it
make the item findable, connectable, or teachable inside Stello? If it's only impressive on
the platform, it stays on the platform.

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
