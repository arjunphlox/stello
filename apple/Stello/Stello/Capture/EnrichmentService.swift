import Foundation
import SwiftData

enum EnrichmentService {

    // MARK: - Apply result to item

    static func apply(
        _ result: EnrichmentResult,
        to item: Item,
        context: ModelContext
    ) throws {
        let existingNames = Set((item.tags ?? []).map { $0.name.lowercased() })
        var names = existingNames

        for spec in result.visionTags {
            let key = spec.name.lowercased()
            guard !names.contains(key) else { continue }
            names.insert(key)
            let tag = Tag(name: spec.name, category: spec.category, weight: spec.weight, source: "ai")
            context.insert(tag)
            tag.item = item
        }

        item.enrichmentStatus = "vision_done"

        let existingSnippets = Set((item.snippets ?? []).map { $0.text.lowercased() })
        for text in result.snippets {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !existingSnippets.contains(trimmed.lowercased()) else { continue }
            let snippet = Snippet(text: trimmed, source: "ai")
            context.insert(snippet)
            snippet.item = item
        }

        if !result.whySavedSuggestions.isEmpty {
            item.whySavedSuggestionsJSON = encodeWhySavedSuggestions(result.whySavedSuggestions)
        }

        item.enrichmentStatus = "candidates_done"
        item.enrichmentError = nil
        item.analyzedAt = .now
        item.updatedAt = .now
        try context.save()
    }

    static func markTerminalWithoutAI(item: Item, context: ModelContext) throws {
        item.enrichmentStatus = "candidates_done"
        item.enrichmentError = nil
        item.updatedAt = .now
        try context.save()
    }

    // MARK: - Run enricher

    static func enrich(
        item: Item,
        context: ModelContext,
        enricher: Enricher,
        force: Bool = false
    ) async {
        // Auto-enrichment only advances text_done items; a user-invoked Enrich (force)
        // may re-run terminal states too (candidates_done after an unavailable-AI capture,
        // or error) — but never an in-flight capture that has no text yet.
        if force {
            guard item.enrichmentStatus != "pending" else { return }
        } else {
            guard item.enrichmentStatus == "text_done" else { return }
        }

        // Music items run a dedicated pipeline (deterministic dossier + vision-only AI)
        // that never touches the generic snippets/why-saved text jobs — there is no prose
        // on a platform shell page, and even title+summary text produced junk suggestions.
        // Any item already classified `kind == music` (from capture-time classification)
        // routes here on every call; `force` also attempts the upgrade for an item whose
        // sourceURL classifies as music but that predates this classifier (kind == link).
        if item.kind == ItemKind.music.rawValue {
            _ = await enrichMusic(item: item, context: context, enricher: enricher, refetch: force)
            return
        }
        if force, await enrichMusic(item: item, context: context, enricher: enricher, refetch: true) {
            return
        }

        // Force (user-invoked) Enrich re-fetches the source page first: it backfills a
        // missing cover image and refreshes `extractedText` so the AI jobs see richer text
        // than the ~200-char summary captured at save time. Auto-enrichment (force=false)
        // must not hit the network beyond what capture already did.
        var refetchError: String? = nil
        if force, let sourceURLString = item.sourceURL, let url = URL(string: sourceURLString) {
            print("[refetch] \(item.slug): fetching \(url.absoluteString)")
            if let page = await CaptureService.fetchPage(url: url) {
                let imageSources = (item.images ?? []).map {
                    "\($0.source)/primary:\($0.isPrimary)/renderable:\($0.hasRenderableCoverData)"
                }
                print("[refetch] \(item.slug): images=[\(imageSources.joined(separator: ", "))] ogImage=\(page.og.imageURL?.absoluteString ?? "nil")")
                await upgradeCoverIfNeeded(
                    item: item, context: context, primaryURL: page.og.imageURL, fallbackURL: nil, source: "og"
                )
                if let extracted = CaptureService.extractText(html: page.html), !extracted.isEmpty {
                    print("[refetch] \(item.slug): extractedText \(extracted.count) chars")
                    item.extractedText = extracted
                    item.updatedAt = .now
                }
            } else {
                print("[refetch] \(item.slug): page fetch FAILED")
                refetchError = "page re-fetch failed: unable to fetch page"
            }
        } else if force {
            print("[refetch] \(item.slug): skipped — sourceURL=\(item.sourceURL ?? "nil")")
        }

        do {
            guard enricher.isAvailable else {
                try markTerminalWithoutAI(item: item, context: context)
                // AI produced nothing (never ran) — surface the refetch failure instead of
                // the silent nil error markTerminalWithoutAI just wrote.
                if let refetchError {
                    item.enrichmentError = refetchError
                    item.updatedAt = .now
                    try? context.save()
                }
                return
            }

            let coverData = item.images?.first(where: \.isPrimary)?.data
                ?? item.images?.first?.data

            let result = try await enricher.enrich(
                title: item.title,
                summary: item.summary,
                domain: item.domain,
                coverImageData: coverData,
                pageText: item.extractedText
            )
            try apply(result, to: item, context: context)
        } catch EnricherError.unavailable {
            try? markTerminalWithoutAI(item: item, context: context)
            if let refetchError {
                item.enrichmentError = refetchError
                item.updatedAt = .now
                try? context.save()
            }
        } catch {
            // AI jobs also produced nothing here — fold the refetch failure in rather than
            // dropping it, but never let it clobber a successful run (that path is `apply`,
            // which explicitly sets enrichmentError to nil and never reaches this catch).
            var message = error.localizedDescription
            if let refetchError {
                message += " (\(refetchError))"
            }
            item.enrichmentError = message
            item.updatedAt = .now
            try? context.save()
        }
    }

    // MARK: - whySaved JSON helpers

    static func encodeWhySavedSuggestions(_ suggestions: [String]) -> String? {
        guard !suggestions.isEmpty,
              let data = try? JSONEncoder().encode(suggestions),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    static func decodeWhySavedSuggestions(from json: String?) -> [String] {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return decoded
    }

    // MARK: - Intent tag from suggestion

    static func addIntentTag(
        name: String,
        to item: Item,
        context: ModelContext,
        removeFromSuggestions: Bool = true
    ) throws {
        let key = name.lowercased()
        let existing = (item.tags ?? []).contains { $0.name.lowercased() == key }
        if !existing {
            let tag = Tag(name: name, category: "intent", weight: 0.9, source: "manual")
            context.insert(tag)
            tag.item = item
        }

        if removeFromSuggestions, let json = item.whySavedSuggestionsJSON {
            let remaining = decodeWhySavedSuggestions(from: json)
                .filter { $0.lowercased() != key }
            item.whySavedSuggestionsJSON = encodeWhySavedSuggestions(remaining)
            if remaining.isEmpty {
                item.needsReview = false
            }
        }

        item.updatedAt = .now
        try context.save()
    }

    static func dismissWhySavedSuggestion(
        name: String,
        from item: Item,
        context: ModelContext
    ) throws {
        guard item.whySavedSuggestionsJSON != nil else { return }
        let key = name.lowercased()
        let remaining = decodeWhySavedSuggestions(from: item.whySavedSuggestionsJSON)
            .filter { $0.lowercased() != key }
        item.whySavedSuggestionsJSON = encodeWhySavedSuggestions(remaining)
        if remaining.isEmpty {
            item.needsReview = false
        }
        item.updatedAt = .now
        try context.save()
    }

    // MARK: - Cover upgrade (shared by the generic refetch path and music extraction)

    /// Upgrades a renderable-but-placeholder cover (`source == "generated"`) to a real
    /// downloaded image, or adds a first cover when none exists. A pre-existing REAL cover
    /// (any source other than "generated") is left untouched.
    static func upgradeCoverIfNeeded(
        item: Item,
        context: ModelContext,
        primaryURL: URL?,
        fallbackURL: URL?,
        source: String
    ) async {
        let hasRealCover = (item.images ?? []).contains {
            $0.hasRenderableCoverData && $0.source != "generated"
        }
        guard !hasRealCover else { return }

        var downloaded: (Data, Int, Int)? = nil
        if let primaryURL { downloaded = await CaptureService.downloadImage(url: primaryURL) }
        if downloaded == nil, let fallbackURL { downloaded = await CaptureService.downloadImage(url: fallbackURL) }
        guard let (data, w, h) = downloaded else { return }

        for placeholder in (item.images ?? []) where placeholder.source == "generated" {
            context.delete(placeholder)
        }
        let image = ItemImage(data: data, source: source, isPrimary: true, width: w, height: h)
        context.insert(image)
        image.item = item
    }

    // MARK: - Music enrichment pipeline

    /// Music-specific why-saved vocabulary — replaces the generic AI job entirely (spec:
    /// never `color-contrast-study` on an album).
    static func musicWhySavedSuggestions(subtype: String?) -> [String] {
        switch subtype {
        case "playlist": return ["studio-playlist", "focus-music", "reference-ambience"]
        case "artist": return ["artist-reference"]
        default: return ["project-soundtrack", "focus-music", "sleeve-design-reference"]
        }
    }

    private static let genreMoodMap: [(keywords: [String], mood: String)] = [
        (["ambient", "chill", "chillout", "lo-fi", "lofi", "downtempo"], "calm"),
        (["classical", "jazz", "orchestral"], "elegant"),
        (["electronic", "dance", "edm", "house", "techno", "trance"], "energetic"),
        (["metal", "punk", "hardcore", "industrial"], "dark"),
        (["soundtrack", "score", "film score"], "dramatic"),
    ]

    /// Static genre → mood table feeding the shared mood tag facet (source "rule", weight
    /// 0.6) — this is the crossover that ties music saves into the same taste graph as
    /// visual saves.
    static func moodTags(forGenres genres: [String]) -> [String] {
        var moods: [String] = []
        for genre in genres {
            let lower = genre.lowercased()
            for entry in genreMoodMap where entry.keywords.contains(where: { lower.contains($0) }) {
                if !moods.contains(entry.mood) { moods.append(entry.mood) }
            }
        }
        return moods
    }

    /// Runs the dedicated music pipeline. For an item already `kind == "music"`, `refetch`
    /// controls whether MusicMeta is rebuilt over the network (force only) or reuses what
    /// capture already stored (auto path — no extra network beyond capture time). For an
    /// item not yet classified as music, this attempts the upgrade (always fetches) and
    /// returns `false` without side effects if the URL doesn't confirm as music, so the
    /// caller falls through to the generic pipeline. Returns `true` when the music pipeline
    /// ran to completion (item is left at a terminal enrichmentStatus either way).
    @discardableResult
    static func enrichMusic(
        item: Item,
        context: ModelContext,
        enricher: Enricher,
        refetch: Bool
    ) async -> Bool {
        let wasAlreadyMusic = item.kind == ItemKind.music.rawValue

        if refetch || !wasAlreadyMusic {
            guard let sourceURLString = item.sourceURL, let url = URL(string: sourceURLString) else {
                if !wasAlreadyMusic { return false }
                return await finishMusicEnrichment(item: item, context: context, enricher: enricher)
            }
            let dom = CaptureService.domain(from: url)
            let looksLikeMusic = wasAlreadyMusic
                || (dom.map { PageClassifier.musicPlatform(forHost: $0) != nil || PageClassifier.isPlainYouTubeHost($0) } ?? false)
            guard looksLikeMusic else { return false }

            let page = await CaptureService.fetchPage(url: url)
            guard let result = await CaptureService.classifyAndExtractMusic(
                sourceURL: url, domain: dom, title: page?.og.title ?? item.title,
                ogType: page?.og.ogType, page: page
            ) else {
                return false
            }

            item.setMetadata(result.meta)
            item.kind = ItemKind.music.rawValue
            await upgradeCoverIfNeeded(
                item: item, context: context,
                primaryURL: result.coverImageURL, fallbackURL: result.coverFallbackURL,
                source: "music"
            )
        }

        return await finishMusicEnrichment(item: item, context: context, enricher: enricher)
    }

    private static func finishMusicEnrichment(
        item: Item, context: ModelContext, enricher: Enricher
    ) async -> Bool {
        guard item.kind == ItemKind.music.rawValue else { return false }

        // Music items never carry page prose — no snippets/why-saved job has one to work
        // from, so any stale extractedText from a prior generic capture is purged.
        if item.extractedText != nil {
            item.extractedText = nil
        }

        let meta = item.musicMeta() ?? MusicMeta()

        item.whySavedSuggestionsJSON = encodeWhySavedSuggestions(musicWhySavedSuggestions(subtype: meta.subtype))

        let existingNames = Set((item.tags ?? []).map { $0.name.lowercased() })
        for mood in moodTags(forGenres: meta.genres) where !existingNames.contains(mood) {
            let tag = Tag(name: mood, category: "mood", weight: 0.6, source: "rule")
            context.insert(tag)
            tag.item = item
        }

        // Vision is the only AI job music items still run — a sleeve is a design reference
        // in its own right (palette, typography, style tags).
        let coverData = item.images?.first(where: \.isPrimary)?.data ?? item.images?.first?.data
        if enricher.isAvailable, let coverData {
            do {
                let visionTags = try await enricher.enrichVisionOnly(coverImageData: coverData)
                let existingAfterMood = Set((item.tags ?? []).map { $0.name.lowercased() })
                for spec in visionTags where !existingAfterMood.contains(spec.name.lowercased()) {
                    let tag = Tag(name: spec.name, category: spec.category, weight: spec.weight, source: "ai")
                    context.insert(tag)
                    tag.item = item
                }
                item.enrichmentError = nil
            } catch {
                item.enrichmentError = "vision: \(error.localizedDescription)"
            }
        }

        // YouTube-sourced compound titles get an AI refine pass over the rule-based split.
        if let fm = enricher as? FoundationModelsEnricher, fm.isAvailable,
           meta.platform == "youtube" || meta.platform == "youtube-music",
           item.title.contains(" - ") || item.title.contains("|") {
            if let refined = try? await fm.enrichMusicTitle(rawTitle: item.title, channel: meta.artists.first?.name) {
                var refinedMeta = item.musicMeta() ?? meta
                if let track = refined.track?.trimmingCharacters(in: .whitespacesAndNewlines), !track.isEmpty {
                    refinedMeta.cleanTitle = track
                }
                if let artist = refined.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty,
                   refinedMeta.artists.isEmpty {
                    refinedMeta.artists = [EntityRef(name: artist, slug: nil, kind: ItemKind.individual.rawValue)]
                }
                if let film = refined.film?.trimmingCharacters(in: .whitespacesAndNewlines), !film.isEmpty {
                    refinedMeta.film = film
                }
                item.setMetadata(refinedMeta)
            }
        }

        item.enrichmentStatus = "candidates_done"
        item.analyzedAt = .now
        item.updatedAt = .now
        try? context.save()
        return true
    }
}
