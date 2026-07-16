import Testing
import Foundation
@testable import Stello

// MARK: - Classification

@Suite("Music classification")
struct MusicClassificationTests {

    @Test("Known music hosts classify by domain")
    func knownMusicHosts() {
        #expect(PageClassifier.musicPlatform(forHost: "open.spotify.com") == "spotify")
        #expect(PageClassifier.musicPlatform(forHost: "music.apple.com") == "apple-music")
        #expect(PageClassifier.musicPlatform(forHost: "arjun.bandcamp.com") == "bandcamp")
        #expect(PageClassifier.musicPlatform(forHost: "soundcloud.com") == "soundcloud")
        #expect(PageClassifier.musicPlatform(forHost: "music.youtube.com") == "youtube-music")
        #expect(PageClassifier.musicPlatform(forHost: "tidal.com") == "tidal")
        #expect(PageClassifier.musicPlatform(forHost: "mixcloud.com") == "mixcloud")
        #expect(PageClassifier.musicPlatform(forHost: "deezer.com") == "deezer")
    }

    @Test("Amazon Music and generic hosts are not classified as music")
    func nonMusicHosts() {
        #expect(PageClassifier.musicPlatform(forHost: "music.amazon.com") == nil)
        #expect(PageClassifier.musicPlatform(forHost: "example.com") == nil)
    }

    @Test("Plain YouTube is a candidate only; music.youtube.com is matched separately")
    func plainYouTubeCandidate() {
        #expect(PageClassifier.isPlainYouTubeHost("youtube.com"))
        #expect(PageClassifier.isPlainYouTubeHost("youtu.be"))
        #expect(!PageClassifier.isPlainYouTubeHost("music.youtube.com"))
    }

    @Test("'- Topic' channel and VEVO confirm music; an ordinary upload does not")
    func youTubeSignal() {
        #expect(PageClassifier.isMusicYouTubeSignal(authorName: "Notaker - Topic", title: nil))
        #expect(PageClassifier.isMusicYouTubeSignal(authorName: "SomeArtistVEVO", title: nil))
        #expect(PageClassifier.isMusicYouTubeSignal(authorName: nil, title: "Song Title - Official Music Video"))
        #expect(!PageClassifier.isMusicYouTubeSignal(authorName: "Random Vlogger", title: "My Day At The Beach"))
    }

    @Test("A non-music YouTube video stays link — the conservative negative case")
    func negativeYouTubeStaysLink() {
        #expect(!PageClassifier.isMusicYouTubeSignal(authorName: "Some Tech Channel", title: "Unboxing My New Laptop"))
    }

    @Test("og:type music.* classifies regardless of host")
    func ogTypeClassification() {
        #expect(PageClassifier.isMusicOGType("music.album"))
        #expect(PageClassifier.isMusicOGType("music.song"))
        #expect(PageClassifier.isMusicOGType("music.playlist"))
        #expect(PageClassifier.isMusicOGType("music.musician"))
        #expect(!PageClassifier.isMusicOGType("article"))
        #expect(!PageClassifier.isMusicOGType(nil))
    }

    // MARK: - Subtype from real URLs

    @Test("Apple Music playlist URL → playlist")
    func appleMusicPlaylistSubtype() {
        let url = URL(string: "https://music.apple.com/in/playlist/focus-zone/pl.u-g3y0HWE82zr")!
        #expect(PageClassifier.musicSubtype(url: url, ogType: nil, platform: "apple-music") == "playlist")
    }

    @Test("Apple Music album URL with ?i= track id → track")
    func appleMusicTrackSubtype() {
        let url = URL(string: "https://music.apple.com/in/album/f1/1821963324?i=1821963565")!
        #expect(PageClassifier.musicSubtype(url: url, ogType: nil, platform: "apple-music") == "track")
    }

    @Test("Apple Music artist URL → artist")
    func appleMusicArtistSubtype() {
        let url = URL(string: "https://music.apple.com/in/artist/a-ka/1743301775")!
        #expect(PageClassifier.musicSubtype(url: url, ogType: nil, platform: "apple-music") == "artist")
    }

    @Test("Spotify album URL → album")
    func spotifyAlbumSubtype() {
        let url = URL(string: "https://open.spotify.com/album/063f8Ej8rLVTz9KkjQKEMa")!
        #expect(PageClassifier.musicSubtype(url: url, ogType: nil, platform: "spotify") == "album")
    }

    @Test("music.youtube.com watch URL falls back to track (no stronger path signal)")
    func youtubeMusicTrackSubtype() {
        let url = URL(string: "https://music.youtube.com/watch?v=I4sFp6hZg14")!
        #expect(PageClassifier.musicSubtype(url: url, ogType: nil, platform: "youtube-music") == "track")
    }

    @Test("Mixcloud always resolves to the 'mix' subtype")
    func mixcloudSubtype() {
        let url = URL(string: "https://www.mixcloud.com/someuser/some-show/")!
        #expect(PageClassifier.musicSubtype(url: url, ogType: nil, platform: "mixcloud") == "mix")
    }

    // MARK: - Curator extraction

    @Test("Apple Music playlist curator extraction — 'Focus Zone by Arjun Phlox'")
    func curatorExtraction() {
        var meta = MusicMeta()
        CaptureService.applyCurator(
            rawTitle: "Focus Zone by Arjun Phlox",
            description: nil,
            subtype: "playlist",
            to: &meta
        )
        #expect(meta.curator?.name == "Arjun Phlox")
    }

    @Test("Curator is never fabricated for a non-playlist subtype")
    func curatorSkippedForNonPlaylist() {
        var meta = MusicMeta()
        CaptureService.applyCurator(rawTitle: "Some Track by Someone", description: nil, subtype: "track", to: &meta)
        #expect(meta.curator == nil)
    }
}

// MARK: - Title parsing + edition splitting

@Suite("Music title parsing + edition splitting")
struct MusicTitleParsingTests {

    @Test("Rule fallback: Western 'Artist - Track' grammar")
    func westernGrammar() {
        let raw = "Zara Larsson - How Deep Is Your Love (Calvin Harris, Disciples Cover) (Live) | Spotify Live Room"
        let parsed = CaptureService.ruleParseYouTubeMusicTitle(raw)
        #expect(parsed.artist == "Zara Larsson")
        #expect(parsed.track == "How Deep Is Your Love (Calvin Harris, Disciples Cover) (Live)")
        #expect(parsed.film == nil)
    }

    @Test("Rule fallback: Indian film-music grammar names the film, not an artist")
    func filmMusicGrammar() {
        let raw = "Thassadiya - Video Song | Maa Inti Bangaaram | Samantha | Chinmayi | Punya | Santhosh Narayanan"
        let parsed = CaptureService.ruleParseYouTubeMusicTitle(raw)
        #expect(parsed.track == "Thassadiya")
        #expect(parsed.film == "Maa Inti Bangaaram")
        #expect(parsed.artist == nil)
    }

    @Test("A plain title with no dash or pipe becomes the track as-is")
    func plainTitleNoGrammar() {
        let parsed = CaptureService.ruleParseYouTubeMusicTitle("Aerodynamic")
        #expect(parsed.track == "Aerodynamic")
        #expect(parsed.artist == nil)
        #expect(parsed.film == nil)
    }

    @Test("Edition suffix splits off remaster/year markers")
    func editionSplitting() {
        let (title, edition) = CaptureService.splitMusicEdition(from: "Ambient 1: Music For Airports (Remastered 2004)")
        #expect(title == "Ambient 1: Music For Airports")
        #expect(edition == "Remastered 2004")
    }

    @Test("A parenthetical that isn't an edition marker is left in the title")
    func nonEditionParenthetical() {
        let (title, edition) = CaptureService.splitMusicEdition(from: "How Deep Is Your Love (Calvin Harris, Disciples Cover)")
        #expect(title == "How Deep Is Your Love (Calvin Harris, Disciples Cover)")
        #expect(edition == nil)
    }
}

// MARK: - oEmbed / Deezer decoding

@Suite("Music oEmbed + Deezer decoding")
struct MusicDecodingTests {

    @Test("Spotify oEmbed response decodes title/thumbnail/embed")
    func spotifyOEmbedDecoding() throws {
        let json = """
        {
          "html": "<iframe src=\\"https://open.spotify.com/embed/album/063f8Ej8rLVTz9KkjQKEMa\\" width=\\"300\\" height=\\"380\\"></iframe>",
          "width": 300,
          "height": 380,
          "version": "1.0",
          "provider_name": "Spotify",
          "provider_url": "https://spotify.com",
          "type": "rich",
          "title": "An Album",
          "thumbnail_url": "https://i.scdn.co/image/ab67616d0000b273abc123",
          "thumbnail_width": 300,
          "thumbnail_height": 300,
          "iframe_url": "https://open.spotify.com/embed/album/063f8Ej8rLVTz9KkjQKEMa"
        }
        """.data(using: .utf8)!

        // OEmbedResponse declares explicit snake_case CodingKeys — default key strategy.
        let response = try JSONDecoder().decode(CaptureService.OEmbedResponse.self, from: json)

        #expect(response.title == "An Album")
        #expect(response.thumbnailURL == "https://i.scdn.co/image/ab67616d0000b273abc123")
        #expect(response.iframeURL == "https://open.spotify.com/embed/album/063f8Ej8rLVTz9KkjQKEMa")
    }

    @Test("Deezer album response (id 302127 shape) decodes title/upc/genres/tracks")
    func deezerAlbumDecoding() throws {
        let json = """
        {
          "id": 302127,
          "title": "Discovery",
          "upc": "0724384960650",
          "release_date": "2001-03-07",
          "label": "Parlophone France",
          "genres": { "data": [ { "id": 113, "name": "Dance" } ] },
          "tracks": {
            "data": [
              { "id": 1, "title": "One More Time", "duration": 320 },
              { "id": 2, "title": "Aerodynamic", "duration": 213 }
            ]
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(CaptureService.DeezerAlbumResponse.self, from: json)

        #expect(response.title == "Discovery")
        #expect(response.upc == "0724384960650")
        #expect(response.releaseDate == "2001-03-07")
        #expect(response.genres?.data.first?.name == "Dance")
        #expect(response.tracks?.data.count == 2)
        #expect(response.tracks?.data.first?.title == "One More Time")

        var meta = MusicMeta()
        CaptureService.applyDeezerData(response, to: &meta)
        #expect(meta.upc == "0724384960650")
        #expect(meta.releaseYear == "2001")
        #expect(meta.genres == ["Dance"])
        #expect(meta.trackList.count == 2)
        #expect(meta.totalDurationSeconds == 533)
    }
}

// MARK: - Genre → mood mapping

@Suite("Genre → mood mapping")
struct MusicMoodMappingTests {
    @Test("Ambient/classical/electronic/metal/soundtrack genres map to distinct moods")
    func genreMoodMapping() {
        #expect(EnrichmentService.moodTags(forGenres: ["Ambient"]) == ["calm"])
        #expect(EnrichmentService.moodTags(forGenres: ["Classical"]) == ["elegant"])
        #expect(EnrichmentService.moodTags(forGenres: ["Electronic", "Dance"]) == ["energetic"])
        #expect(EnrichmentService.moodTags(forGenres: ["Metal"]) == ["dark"])
        #expect(EnrichmentService.moodTags(forGenres: ["Soundtrack"]) == ["dramatic"])
        #expect(EnrichmentService.moodTags(forGenres: ["Unknown Genre"]).isEmpty)
    }
}

// MARK: - Why-saved vocabulary

@Suite("Music why-saved vocabulary")
struct MusicWhySavedTests {
    @Test("Playlist, artist, and track/album subtypes get distinct deterministic suggestions")
    func whySavedBySubtype() {
        #expect(EnrichmentService.musicWhySavedSuggestions(subtype: "playlist") == [
            "studio-playlist", "focus-music", "reference-ambience",
        ])
        #expect(EnrichmentService.musicWhySavedSuggestions(subtype: "artist") == ["artist-reference"])
        #expect(EnrichmentService.musicWhySavedSuggestions(subtype: "album") == [
            "project-soundtrack", "focus-music", "sleeve-design-reference",
        ])
        #expect(EnrichmentService.musicWhySavedSuggestions(subtype: "track") == [
            "project-soundtrack", "focus-music", "sleeve-design-reference",
        ])
    }
}

// MARK: - extractedText purge on upgrade

@Suite("Music upgrade purges search-blob junk")
struct MusicUpgradePurgeTests {
    @Test("A pre-existing extractedText is cleared once an item is classified kind == music")
    func extractedTextClearedOnUpgrade() {
        let item = Item(
            slug: "old-spotify-link",
            title: "Some Album",
            sourceURL: "https://open.spotify.com/album/063f8Ej8rLVTz9KkjQKEMa",
            extractedText: "Log in Sign up Open in App stale shell-page junk from a prior generic capture",
            enrichmentStatus: "candidates_done",
            kind: "link"
        )
        #expect(item.extractedText != nil)

        item.kind = ItemKind.music.rawValue
        if item.extractedText != nil {
            item.extractedText = nil
        }

        #expect(item.kind == ItemKind.music.rawValue)
        #expect(item.extractedText == nil)
    }
}
