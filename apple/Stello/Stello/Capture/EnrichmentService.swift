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
                if page.isGone, item.status != "gone" {
                    item.status = "gone"
                    item.updatedAt = .now
                }
                // Post readers first (kind order: post → product), then product readers: a
                // link item may now classify as either (collection labels can decide — a
                // wishlisted post is a product), and a post/product refreshes its dossier.
                let postPlatform = await refreshPostIfClassified(
                    item: item, context: context, url: url, page: page
                )
                // Resource readers next (kind order: post → resource → product → tool) — ahead
                // of product, since Framer Marketplace pages carry Product JSON-LD with offers.
                var isResource = false
                if postPlatform == nil {
                    isResource = await refreshResourceIfClassified(
                        item: item, context: context, url: url, page: page
                    )
                }
                var productSource: String? = nil
                if postPlatform == nil, !isResource {
                    productSource = await refreshProductIfClassified(
                        item: item, context: context, url: url, page: page
                    )
                }
                // Tool readers next (kind order: post → resource → product → tool → article).
                var isTool = false
                if postPlatform == nil, !isResource, productSource == nil {
                    isTool = await refreshToolIfClassified(item: item, context: context, url: url, page: page)
                }
                // Article readers last.
                if postPlatform == nil, !isResource, productSource == nil, !isTool {
                    await refreshArticleIfClassified(item: item, context: context, url: url, page: page)
                }
                await upgradeCoverIfNeeded(
                    item: item, context: context, primaryURL: page.og.imageURL, fallbackURL: nil, source: "og"
                )
                if postPlatform != nil {
                    // Social shell pages have no prose — the post text is it.
                    if let text = item.postMeta()?.text {
                        item.extractedText = text
                        item.updatedAt = .now
                    }
                } else if productSource == nil || productSource == "page" {
                    if let extracted = CaptureService.extractText(html: page.html), !extracted.isEmpty {
                        print("[refetch] \(item.slug): extractedText \(extracted.count) chars")
                        item.extractedText = extracted
                        item.updatedAt = .now
                    }
                } else if let caption = item.productMeta()?.caption {
                    // Instagram shell pages / image bytes have no prose — the caption is it.
                    item.extractedText = caption
                    item.updatedAt = .now
                }
            } else {
                print("[refetch] \(item.slug): page fetch FAILED")
                refetchError = "page re-fetch failed: unable to fetch page"
            }
        } else if force {
            print("[refetch] \(item.slug): skipped — sourceURL=\(item.sourceURL ?? "nil")")
        }

        // Instagram / bare-image products have no structured name or brand — guess them
        // (on-device model, rule-based fallback) before the generic AI jobs run.
        if item.kind == ItemKind.product.rawValue {
            await applyProductGuessIfNeeded(item: item, enricher: enricher)
        }
        // Tools with no platforms / pricing read: guess them from the page text (on-device
        // model, then the conservative rule-based keyword pass).
        if item.kind == ItemKind.tool.rawValue {
            await applyToolGuessIfNeeded(item: item, enricher: enricher)
        }
        // Articles with no summary yet: on-device summary (+ tech stack for tutorials; the
        // rule-based names when the model gives none).
        if item.kind == ItemKind.article.rawValue {
            await applyArticleDigestIfNeeded(item: item, enricher: enricher)
        }
        // Posts: AI-art flag from collection labels / tags / Midjourney params, then the
        // prompt (rule-read, else the on-device guess).
        if item.kind == ItemKind.post.rawValue {
            await applyPostAIArtIfNeeded(item: item, enricher: enricher)
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

    // MARK: - Product enrichment

    /// Collection labels (`category == "collection"` tags: wishlist, digital-tools, …) —
    /// hints that break classification ties; imported items carry them, fresh captures don't.
    static func collectionLabels(for item: Item) -> [String] {
        (item.tags ?? []).filter { $0.category == "collection" }.map(\.name)
    }

    /// Force-Enrich hook: when a `link` or `product` item's refetched page classifies as a
    /// product, (re)runs the product readers and stores the dossier. "Price when saved" is a
    /// snapshot — an existing price/date is never rewritten — and a read (non-guess)
    /// name/brand is never replaced by a guess. Returns the product source, or nil when the
    /// item isn't (or can't become) a product. Curated kinds (typeface, website, …) are
    /// never flipped.
    @discardableResult
    static func refreshProductIfClassified(
        item: Item,
        context: ModelContext,
        url: URL,
        page: PageFetchResult
    ) async -> String? {
        guard item.kind == ItemKind.link.rawValue || item.kind == ItemKind.product.rawValue else { return nil }
        guard let source = PageClassifier.productSource(
            url: url, ogType: page.og.ogType, html: page.html, collectionLabels: collectionLabels(for: item)
        ) else { return nil }

        let extraction = await CaptureService.extractProduct(sourceURL: url, page: page, source: source)
        var meta = extraction.meta
        if let previous = item.productMeta() {
            if previous.price != nil {
                meta.price = previous.price
                meta.priceMin = previous.priceMin
                meta.priceMax = previous.priceMax
                meta.currency = previous.currency
                meta.pricedAt = previous.pricedAt
            }
            if previous.productName != nil, meta.productName == nil || meta.productNameIsGuess == true {
                meta.productName = previous.productName
                meta.productNameIsGuess = previous.productNameIsGuess
            }
            if previous.brand != nil, meta.brand == nil || meta.brandIsGuess == true {
                meta.brand = previous.brand
                meta.brandIsGuess = previous.brandIsGuess
            }
        }

        item.kind = ItemKind.product.rawValue
        item.setMetadata(meta)
        if let finalURL = page.finalURL, let landed = CaptureService.domain(from: finalURL) {
            item.domain = landed
        }

        await upgradeCoverIfNeeded(
            item: item, context: context,
            primaryURL: extraction.imageURLs.first, fallbackURL: nil, source: "product"
        )
        let hasGallery = (item.images ?? []).contains { $0.role == ItemImageRole.gallery.rawValue }
        if !hasGallery {
            let downloads = await CaptureService.downloadImages(Array(extraction.imageURLs.dropFirst()))
            for (data, w, h) in downloads.compactMap({ $0 }) {
                let image = ItemImage(
                    data: data, source: "product", isPrimary: false, width: w, height: h,
                    role: ItemImageRole.gallery.rawValue
                )
                context.insert(image)
                image.item = item
            }
        }
        item.updatedAt = .now
        return source
    }

    /// Instagram / bare-image products: guess name + brand from the caption or filename
    /// (on-device model; the rule-based filename reading when the model is unavailable,
    /// fails, or returns nothing). Stored with the `…IsGuess` flags; read values win.
    static func applyProductGuessIfNeeded(item: Item, enricher: Enricher) async {
        guard var meta = item.productMeta(),
              meta.source == "instagram" || meta.source == "image" else { return }
        let needsName = meta.productName == nil || meta.productNameIsGuess == true
        let needsBrand = meta.brand == nil || meta.brandIsGuess == true
        guard needsName || needsBrand else { return }

        let filename: String? = meta.source == "image"
            ? item.sourceURL.flatMap { URL(string: $0) }?.lastPathComponent
            : nil
        let caption = meta.caption
        guard caption != nil || filename != nil else { return }

        let ruleGuess = ProductReader.ruleBasedGuess(caption: caption, filename: filename)
        var guess: ProductGuess
        do {
            guess = try await enricher.guessProduct(caption: caption, filename: filename)
        } catch {
            guess = ruleGuess
        }
        if guess.productName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            guess.productName = ruleGuess.productName
        }

        let previousName = meta.productName
        ProductReader.applyGuess(guess, to: &meta)
        item.setMetadata(meta)
        // A title that was itself the old guess follows the new one.
        if let previousName, item.title == previousName, let newName = meta.productName {
            item.title = newName
        }
        item.updatedAt = .now
    }

    // MARK: - Post enrichment

    /// Force-Enrich hook: when a `link` or `post` item's refetched URL is a single social
    /// post (and not wishlisted — that's a product), (re)runs the post readers and stores the
    /// dossier. A refetch that reads less (bot wall, tombstone) never erases what capture
    /// read, and the AI-art fields are left to `applyPostAIArtIfNeeded`. The title rule only
    /// replaces a generic platform title or the title this rule wrote before — a title the
    /// user edited is kept. Returns the platform, or nil when the item isn't (or can't
    /// become) a post. Curated kinds (typeface, website, product, …) are never flipped.
    @discardableResult
    static func refreshPostIfClassified(
        item: Item,
        context: ModelContext,
        url: URL,
        page: PageFetchResult
    ) async -> String? {
        guard item.kind == ItemKind.link.rawValue || item.kind == ItemKind.post.rawValue else { return nil }
        guard let platform = PageClassifier.postPlatform(
            url: url, collectionLabels: collectionLabels(for: item)
        ) else { return nil }

        let extraction = await CaptureService.extractPost(sourceURL: url, page: page, platform: platform)
        var meta = extraction.meta
        let previous = item.postMeta()
        if let previous {
            if meta.text == nil { meta.text = previous.text }
            if meta.author == nil { meta.author = previous.author }
            if meta.authorHandle == nil { meta.authorHandle = previous.authorHandle }
            if meta.postedAt == nil { meta.postedAt = previous.postedAt }
            if meta.mediaType == nil {
                meta.mediaType = previous.mediaType
                meta.mediaCount = previous.mediaCount
            }
            if meta.embedURL == nil { meta.embedURL = previous.embedURL }
            meta.isAIArt = previous.isAIArt
            meta.aiModel = previous.aiModel
            meta.prompt = previous.prompt
            meta.promptIsGuess = previous.promptIsGuess
        }

        // The title this rule would have written from the old dossier — if the item still
        // carries it, the user hasn't edited it and it may follow the new reading.
        let previousRuleTitle = previous.flatMap {
            PostReader.postTitle(currentTitle: nil, handle: $0.authorHandle, authorName: $0.author?.name, text: $0.text)
        }
        let titleIsOurs = PostReader.isGenericPostTitle(item.title) || item.title == previousRuleTitle
        if titleIsOurs, let newTitle = PostReader.postTitle(
            currentTitle: nil, handle: meta.authorHandle, authorName: meta.author?.name, text: meta.text
        ) {
            item.title = newTitle
        }

        if extraction.isGone, item.status != "gone" {
            item.status = "gone"
        }
        item.kind = ItemKind.post.rawValue
        item.setMetadata(meta)

        await upgradeCoverIfNeeded(
            item: item, context: context,
            primaryURL: extraction.imageURLs.first, fallbackURL: nil, source: "post"
        )
        let hasGallery = (item.images ?? []).contains { $0.role == ItemImageRole.gallery.rawValue }
        if !hasGallery {
            let downloads = await CaptureService.downloadImages(Array(extraction.imageURLs.dropFirst()))
            for (data, w, h) in downloads.compactMap({ $0 }) {
                let image = ItemImage(
                    data: data, source: "post", isPrimary: false, width: w, height: h,
                    role: ItemImageRole.gallery.rawValue
                )
                context.insert(image)
                image.item = item
            }
        }
        item.updatedAt = .now
        return platform
    }

    /// Posts: recompute the AI-art flag + model from collection labels, tags and Midjourney
    /// params in the text, then fill the prompt — rule-read first (`promptIsGuess == false`),
    /// else the on-device guess (`promptIsGuess == true`; the Mock / rule-based fallbacks
    /// return nil). Labels only ever flag items that are already Post.
    static func applyPostAIArtIfNeeded(item: Item, enricher: Enricher) async {
        guard var meta = item.postMeta() else { return }
        let labels = collectionLabels(for: item)
        let tags = (item.tags ?? []).filter { $0.category != "collection" }.map(\.name)
        PostReader.applyAIArt(to: &meta, labels: labels, tags: tags)

        if meta.isAIArt, meta.prompt == nil, meta.text != nil {
            if let guess = try? await enricher.guessPrompt(text: meta.text, aiModel: meta.aiModel),
               let prompt = PostReader.cleanPrompt(guess) {
                meta.prompt = prompt
                meta.promptIsGuess = true
            }
        }

        item.setMetadata(meta)
        item.updatedAt = .now
    }

    // MARK: - Tool enrichment

    /// Force-Enrich hook: when a `link` or `tool` item's refetched page classifies as a tool
    /// (after post and product — the caller only runs this when neither claimed it), (re)runs
    /// the tool readers and stores the dossier. A refetch that reads less (rate-limited
    /// GitHub, bot wall) never erases what capture read, and an earlier guess survives until
    /// something is read in its place. Returns whether the item is a tool. Curated kinds
    /// (typeface, website, product, post, …) are never flipped.
    @discardableResult
    static func refreshToolIfClassified(
        item: Item,
        context: ModelContext,
        url: URL,
        page: PageFetchResult
    ) async -> Bool {
        let wasTool = item.kind == ItemKind.tool.rawValue
        guard wasTool || item.kind == ItemKind.link.rawValue else { return false }
        guard wasTool || PageClassifier.isTool(
            url: url, ogType: page.og.ogType, html: page.html, collectionLabels: collectionLabels(for: item)
        ) else { return false }

        let extraction = await CaptureService.extractTool(sourceURL: url, page: page)
        let meta = ToolReader.merge(fresh: extraction.meta, previous: item.toolMeta())

        item.kind = ItemKind.tool.rawValue
        item.setMetadata(meta)
        if let canonical = meta.canonicalURL.flatMap({ URL(string: $0) }),
           let host = CaptureService.domain(from: canonical) {
            item.domain = host
        }
        item.updatedAt = .now
        return true
    }

    // MARK: - Resource enrichment

    /// Force-Enrich hook: when a `link` or `resource` item's refetched page classifies as a
    /// resource (after post — the caller runs this before product and tool), (re)runs the
    /// resource readers and stores the dossier. A refetch that reads less never erases what
    /// capture read. Returns whether the item is a resource.
    ///
    /// Two earlier-build migrations are also allowed: a `product` item whose URL is a Framer
    /// Marketplace item (those pages carry Product JSON-LD with offers, so builds before the
    /// Resource kind filed them as products), and a `tool` item whose URL is a Figma Community
    /// plugin / widget / file (filed as a tool by label or SoftwareApplication JSON-LD). Every
    /// other curated kind (typeface, website, post, …) is never flipped. No on-device guess.
    @discardableResult
    static func refreshResourceIfClassified(
        item: Item,
        context: ModelContext,
        url: URL,
        page: PageFetchResult
    ) async -> Bool {
        let wasResource = item.kind == ItemKind.resource.rawValue
        let isFlippable = item.kind == ItemKind.link.rawValue
            || (item.kind == ItemKind.product.rawValue && PageClassifier.framerMarketplaceSegment(from: url) != nil)
            || (item.kind == ItemKind.tool.rawValue && PageClassifier.figmaCommunityResourceType(from: url) != nil)
        guard wasResource || isFlippable else { return false }

        let labels = collectionLabels(for: item)
        guard wasResource || PageClassifier.isResource(
            url: url, ogType: page.og.ogType, html: page.html, collectionLabels: labels
        ) else { return false }

        let extraction = CaptureService.extractResource(sourceURL: url, page: page, collectionLabels: labels)
        let meta = ResourceReader.merge(fresh: extraction.meta, previous: item.resourceMeta())

        item.kind = ItemKind.resource.rawValue
        item.setMetadata(meta)
        if let canonical = meta.canonicalURL.flatMap({ URL(string: $0) }),
           let host = CaptureService.domain(from: canonical) {
            item.domain = host
        }
        item.updatedAt = .now
        return true
    }

    // MARK: - Article enrichment

    /// Force-Enrich hook: when a `link` or `article` item's refetched page classifies as an
    /// article (after post, resource, product and tool — the caller only runs this when none
    /// claimed it), (re)runs the article readers and stores the dossier. A refetch that reads
    /// less never erases what capture read, and the on-device summary / tech stack are kept.
    /// Returns whether the item is an article. Curated kinds (typeface, website, product,
    /// post, tool, resource, …) are never flipped.
    @discardableResult
    static func refreshArticleIfClassified(
        item: Item,
        context: ModelContext,
        url: URL,
        page: PageFetchResult
    ) async -> Bool {
        let wasArticle = item.kind == ItemKind.article.rawValue
        guard wasArticle || item.kind == ItemKind.link.rawValue else { return false }
        guard wasArticle || PageClassifier.isArticle(
            url: url, ogType: page.og.ogType, html: page.html, collectionLabels: collectionLabels(for: item)
        ) else { return false }

        let fresh = CaptureService.extractArticle(sourceURL: url, page: page)
        let meta = ArticleReader.merge(fresh: fresh, previous: item.articleMeta())

        item.kind = ItemKind.article.rawValue
        item.setMetadata(meta)
        if let canonical = meta.canonicalURL.flatMap({ URL(string: $0) }),
           let host = CaptureService.domain(from: canonical) {
            item.domain = host
        }
        item.updatedAt = .now
        return true
    }

    /// Articles: when the summary is still empty (or a tutorial has no tech stack), run the
    /// on-device digest over the page text. The summary is stored with `summaryIsGuess`; a
    /// tutorial the model gives no stack for (unavailable, failed, nil — Mock / rule-based)
    /// gets the conservative rule-based names. Stored values are never replaced.
    static func applyArticleDigestIfNeeded(item: Item, enricher: Enricher) async {
        guard var meta = item.articleMeta(), ArticleReader.needsDigest(meta) else { return }
        guard let text = item.extractedText,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var facts: ArticleFacts? = nil
        if meta.summary == nil {
            facts = try? await enricher.summarizeArticle(text: text)
        }
        ArticleReader.applyDigest(facts, text: text, to: &meta)
        item.setMetadata(meta)
        item.updatedAt = .now
    }

    /// Tools: when the readers left platforms or pricing empty, guess them from the page text
    /// (on-device model; the rule-based keyword pass when the model is unavailable, fails or
    /// returns nothing). Stored with the `…IsGuess` flags; read values win.
    static func applyToolGuessIfNeeded(item: Item, enricher: Enricher) async {
        guard var meta = item.toolMeta(), ToolReader.needsGuess(meta) else { return }
        guard let text = item.extractedText ?? item.summary ?? meta.tagline,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let modelGuess: ToolFacts? = try? await enricher.guessToolFacts(text: text)
        guard let guess = modelGuess ?? ToolReader.ruleBasedFacts(text: text) else { return }

        ToolReader.applyGuess(guess, to: &meta)
        item.setMetadata(meta)
        item.updatedAt = .now
    }
}
