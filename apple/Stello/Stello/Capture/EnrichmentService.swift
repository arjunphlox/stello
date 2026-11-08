import Foundation
import SwiftData

enum EnrichmentService {

    // MARK: - Apply result to item

    static func apply(
        _ result: EnrichmentResult,
        to item: Item,
        context: ModelContext
    ) throws {
        var tags = item.tags
        var names = Set(tags.map { $0.name.lowercased() })

        for spec in result.visionTags {
            let key = spec.name.lowercased()
            guard !names.contains(key) else { continue }
            names.insert(key)
            tags.append(ItemTag(name: spec.name, category: spec.category, weight: spec.weight, source: "ai"))
        }
        item.tags = tags

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

        // Force (user-invoked) Enrich re-fetches the source page and asks the Worker's page
        // readers again (an already-typed item is read as its kind): it refreshes the
        // dossier, backfills a missing cover and refreshes `extractedText` so the AI jobs see
        // richer text than the ~200-char summary captured at save time. Auto-enrichment
        // (force=false) must not hit the network beyond what capture already did.
        var refetchError: String? = nil
        if force, let sourceURLString = item.sourceURL, let url = URL(string: sourceURLString) {
            print("[refetch] \(item.slug): fetching \(url.absoluteString)")
            let page = await CaptureService.fetchPage(url: url)
            if page == nil {
                print("[refetch] \(item.slug): page fetch FAILED")
                refetchError = "page re-fetch failed: unable to fetch page"
            }
            if let page, page.isGone, item.status != "gone" {
                item.status = "gone"
                item.updatedAt = .now
            }
            // Without the page the URL and labels still decide (and music reads its oEmbed).
            let read = await WorkerSorter.read(
                url: url, page: page, labels: collectionLabels(for: item),
                asKind: WorkerSorter.asKind(for: item.kind)
            )
            if let read {
                if applyMusicRead(read, to: item) {
                    await upgradeCoverIfNeeded(
                        item: item, context: context,
                        primaryURL: read.imageURLs.first, fallbackURL: read.fallbackImageURLs.first,
                        source: "music"
                    )
                } else {
                    await applyFreshRead(read, to: item, context: context)
                }
            }
            if item.kind != ItemKind.music.rawValue, let page {
                await upgradeCoverIfNeeded(
                    item: item, context: context, primaryURL: page.og.imageURL, fallbackURL: nil, source: "og"
                )
                if item.kind == ItemKind.post.rawValue {
                    // Social shell pages have no prose — the post text is it.
                    if let text = item.postMeta()?.text {
                        item.extractedText = text
                        item.updatedAt = .now
                    }
                } else if item.kind == ItemKind.product.rawValue, let meta = item.productMeta(), meta.source != "page" {
                    // Instagram shell pages / image bytes have no prose — the caption is it.
                    if let caption = meta.caption {
                        item.extractedText = caption
                        item.updatedAt = .now
                    }
                } else if let extracted = read?.extractedText ?? CaptureService.extractText(html: page.html),
                          !extracted.isEmpty {
                    print("[refetch] \(item.slug): extractedText \(extracted.count) chars")
                    item.extractedText = extracted
                    item.updatedAt = .now
                }
            }
        } else if force {
            print("[refetch] \(item.slug): skipped — sourceURL=\(item.sourceURL ?? "nil")")
        }

        // Music items run a dedicated pipeline (deterministic dossier + vision-only AI)
        // that never touches the generic snippets/why-saved text jobs — there is no prose
        // on a platform shell page, and even title+summary text produced junk suggestions.
        if item.kind == ItemKind.music.rawValue {
            _ = await finishMusicEnrichment(item: item, context: context, enricher: enricher)
            return
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
        // Books with no author read: guess the authors (and an empty year) from the page text
        // (on-device model only — nothing rule-based).
        if item.kind == ItemKind.book.rawValue {
            await applyBookGuessIfNeeded(item: item, enricher: enricher)
        }
        // Courses with no format / length / topics read: guess them from the page text
        // (on-device model, then the conservative rule-based keyword pass).
        if item.kind == ItemKind.course.rawValue {
            await applyCourseGuessIfNeeded(item: item, enricher: enricher)
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
        let existing = item.tags.contains { $0.name.lowercased() == key }
        if !existing {
            item.tags.append(ItemTag(name: name, category: "intent", weight: 0.9, source: "manual"))
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

    /// Stores a Worker read that confirmed music (a `link` or `music` item only; the
    /// music readers rebuild the whole dossier). Returns whether it applied.
    static func applyMusicRead(_ read: WorkerRead, to item: Item) -> Bool {
        guard read.kind == .music, let meta = read.metadataJSON,
              item.kind == ItemKind.music.rawValue || item.kind == ItemKind.link.rawValue || item.kind.isEmpty
        else { return false }
        item.metadataJSON = meta
        item.kind = ItemKind.music.rawValue
        item.updatedAt = .now
        return true
    }

    @discardableResult
    static func finishMusicEnrichment(
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

        let existingNames = Set(item.tags.map { $0.name.lowercased() })
        item.tags += moodTags(forGenres: meta.genres)
            .filter { !existingNames.contains($0) }
            .map { ItemTag(name: $0, category: "mood", weight: 0.6, source: "rule") }

        // Vision is the only AI job music items still run — a sleeve is a design reference
        // in its own right (palette, typography, style tags).
        let coverData = item.images?.first(where: \.isPrimary)?.data ?? item.images?.first?.data
        if enricher.isAvailable, let coverData {
            do {
                let visionTags = try await enricher.enrichVisionOnly(coverImageData: coverData)
                let existingAfterMood = Set(item.tags.map { $0.name.lowercased() })
                item.tags += visionTags
                    .filter { !existingAfterMood.contains($0.name.lowercased()) }
                    .map { ItemTag(name: $0.name, category: $0.category, weight: $0.weight, source: "ai") }
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

    // MARK: - Fresh read (force Enrich)

    /// Moves an earlier build's filing on: the Worker answers these only under its
    /// migration rules (Framer Marketplace product, Figma Community tool, course page filed
    /// as an article).
    private static let migrations: Set<String> = ["product>resource", "tool>resource", "article>course"]

    /// Whether a fresh read may be stored on the item: the same kind, a plain link becoming
    /// a reader kind, or a migration. Curated kinds (typeface, website, individual, …) are
    /// never flipped.
    static func canApply(_ read: WorkerRead, to item: Item) -> Bool {
        let current = item.kind.isEmpty ? ItemKind.link.rawValue : item.kind
        guard read.kind != .link, read.metadataJSON != nil else { return false }
        if read.kind.rawValue == current { return true }
        if current == ItemKind.link.rawValue { return WorkerSorter.linkKinds.contains(read.kind) }
        return migrations.contains("\(current)>\(read.kind.rawValue)")
    }

    /// Stores a fresh read over what the item has. A refetch that reads less (bot wall,
    /// rate-limited GitHub, tombstone) never erases what was read before; guesses survive
    /// until a value is read in their place; "price when saved" is a snapshot; the AI-art
    /// fields belong to `applyPostAIArtIfNeeded`; a post title the user edited is kept.
    static func applyFreshRead(_ read: WorkerRead, to item: Item, context: ModelContext) async {
        guard read.kind != .music, canApply(read, to: item) else { return }
        // A migration (product → resource, …) starts fresh: the old kind's dossier is a
        // different shape and must not leak into the new one.
        let sameKind = item.kind == read.kind.rawValue
        switch read.kind {
        case .product:
            guard let fresh = read.meta(ProductMeta.self) else { return }
            item.setMetadata(mergeProduct(fresh: fresh, previous: sameKind ? item.productMeta() : nil))
        case .post:
            guard let fresh = read.meta(PostMeta.self) else { return }
            let previous = sameKind ? item.postMeta() : nil
            let meta = mergePost(fresh: fresh, previous: previous)
            // The title this rule would have written from the old dossier: if the item still
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
            if read.isGone, item.status != "gone" { item.status = "gone" }
            item.setMetadata(meta)
        case .tool:
            guard let fresh = read.meta(ToolMeta.self) else { return }
            item.setMetadata(ToolReader.merge(fresh: fresh, previous: sameKind ? item.toolMeta() : nil))
        case .resource:
            guard let fresh = read.meta(ResourceMeta.self) else { return }
            item.setMetadata(ResourceReader.merge(fresh: fresh, previous: sameKind ? item.resourceMeta() : nil))
        case .book:
            guard let fresh = read.meta(BookMeta.self) else { return }
            item.setMetadata(BookReader.merge(fresh: fresh, previous: sameKind ? item.bookMeta() : nil))
        case .course:
            guard let fresh = read.meta(CourseMeta.self) else { return }
            item.setMetadata(CourseReader.merge(fresh: fresh, previous: sameKind ? item.courseMeta() : nil))
        case .article:
            guard let fresh = read.meta(ArticleMeta.self) else { return }
            item.setMetadata(ArticleReader.merge(fresh: fresh, previous: sameKind ? item.articleMeta() : nil))
        default:
            return
        }
        item.kind = read.kind.rawValue
        if let domain = read.domain { item.domain = domain }

        switch read.kind {
        case .product, .post:
            await upgradeCoverIfNeeded(
                item: item, context: context,
                primaryURL: read.imageURLs.first, fallbackURL: nil, source: read.imageSource
            )
            let hasGallery = (item.images ?? []).contains { $0.role == ItemImageRole.gallery.rawValue }
            if !hasGallery {
                let downloads = await CaptureService.downloadImages(Array(read.imageURLs.dropFirst()))
                for (data, w, h) in downloads.compactMap({ $0 }) {
                    let image = ItemImage(
                        data: data, source: read.imageSource, isPrimary: false, width: w, height: h,
                        role: ItemImageRole.gallery.rawValue
                    )
                    context.insert(image)
                    image.item = item
                }
            }
        case .book:
            // og:image first (each call is a no-op once a real cover exists), then the book covers.
            await upgradeCoverIfNeeded(
                item: item, context: context, primaryURL: read.imageURLs.first, fallbackURL: nil, source: "og"
            )
            let fallbacks = read.fallbackImageURLs
            await upgradeCoverIfNeeded(
                item: item, context: context,
                primaryURL: fallbacks.first, fallbackURL: fallbacks.dropFirst().first, source: "book"
            )
        default:
            break
        }
        item.updatedAt = .now
    }

    /// "Price when saved" is a snapshot (an existing price / date is never rewritten), and a
    /// read (non-guess) name or brand is never replaced by a guess.
    static func mergeProduct(fresh: ProductMeta, previous: ProductMeta?) -> ProductMeta {
        var meta = fresh
        guard let previous else { return meta }
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
        return meta
    }

    /// A refetch that reads less never erases what capture read; the AI-art fields are kept
    /// for `applyPostAIArtIfNeeded`.
    static func mergePost(fresh: PostMeta, previous: PostMeta?) -> PostMeta {
        var meta = fresh
        guard let previous else { return meta }
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
        return meta
    }

    // MARK: - Product enrichment

    /// Collection labels (`category == "collection"` tags: wishlist, digital-tools, …) —
    /// hints that break classification ties; imported items carry them, fresh captures don't.
    static func collectionLabels(for item: Item) -> [String] {
        item.tags.filter { $0.category == "collection" }.map(\.name)
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

    /// Posts: recompute the AI-art flag + model from collection labels, tags and Midjourney
    /// params in the text, then fill the prompt — rule-read first (`promptIsGuess == false`),
    /// else the on-device guess (`promptIsGuess == true`; the Mock / rule-based fallbacks
    /// return nil). Labels only ever flag items that are already Post.
    static func applyPostAIArtIfNeeded(item: Item, enricher: Enricher) async {
        guard var meta = item.postMeta() else { return }
        let labels = collectionLabels(for: item)
        let tags = item.tags.filter { $0.category != "collection" }.map(\.name)
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

    // MARK: - Resource enrichment

    // MARK: - Book enrichment

    /// Books: when the readers (page, JSON-LD, Open Library) left no author, guess the authors
    /// — and an empty year — from the page text (on-device model; Mock / rule-based give
    /// nil). Stored with `authorsAreGuess`; read values win.
    static func applyBookGuessIfNeeded(item: Item, enricher: Enricher) async {
        guard var meta = item.bookMeta(), BookReader.needsGuess(meta) else { return }
        guard let text = item.extractedText ?? item.summary,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard let guess = try? await enricher.guessBookFacts(text: text) else { return }

        BookReader.applyGuess(guess, to: &meta)
        item.setMetadata(meta)
        item.updatedAt = .now
    }

    // MARK: - Course enrichment

    /// Courses: when the readers left the format, length or topics empty, guess them from the
    /// page text (on-device model; the rule-based keyword pass when the model is unavailable,
    /// fails or returns nothing — its lesson count also fills an empty `lessons`). Stored with
    /// the `…IsGuess` flags; read values win.
    static func applyCourseGuessIfNeeded(item: Item, enricher: Enricher) async {
        guard var meta = item.courseMeta(), CourseReader.needsGuess(meta) else { return }
        guard let text = item.extractedText ?? item.summary,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let ruleFacts = CourseReader.ruleBasedFacts(text: text)
        let modelGuess: CourseFacts? = try? await enricher.guessCourseFacts(text: text)
        guard var guess = modelGuess ?? ruleFacts else { return }
        if guess.lessons == nil { guess.lessons = ruleFacts?.lessons }

        CourseReader.applyGuess(guess, to: &meta)
        item.setMetadata(meta)
        item.updatedAt = .now
    }

    // MARK: - Article enrichment

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
