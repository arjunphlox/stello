import Testing
import Foundation
@testable import Stello

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

// MARK: - Album + album artist on tracks

@Suite("Music album + album artist")
@MainActor
struct MusicAlbumTests {

    @Test("Album artist row hides when it matches the track artist")
    func albumArtistRow() {
        var meta = MusicMeta()
        meta.subtype = "track"
        meta.artists = [EntityRef(name: "The Weeknd", slug: nil, kind: "individual")]
        meta.albumArtist = "the weeknd"
        #expect(CardSubcards.musicAlbumArtistRow(meta) == nil)
        meta.albumArtist = "Various Artists"
        #expect(CardSubcards.musicAlbumArtistRow(meta) == "Various Artists")
        meta.subtype = "album"
        #expect(CardSubcards.musicAlbumArtistRow(meta) == nil)
    }

    @Test("Old stored MusicMeta without album fields still decodes")
    func legacyDecode() throws {
        let meta = try JSONDecoder().decode(MusicMeta.self, from: Data(#"{"subtype":"track","artists":[],"genres":[],"trackList":[]}"#.utf8))
        #expect(meta.album == nil)
        #expect(meta.albumArtist == nil)
    }
}
