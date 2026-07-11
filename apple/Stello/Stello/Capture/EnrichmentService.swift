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

        // Force (user-invoked) Enrich re-fetches the source page first: it backfills a
        // missing cover image and refreshes `extractedText` so the AI jobs see richer text
        // than the ~200-char summary captured at save time. Auto-enrichment (force=false)
        // must not hit the network beyond what capture already did.
        var refetchError: String? = nil
        if force, let sourceURLString = item.sourceURL, let url = URL(string: sourceURLString) {
            if let page = await CaptureService.fetchPage(url: url) {
                if !item.hasRenderableCover,
                   let imageURL = page.og.imageURL,
                   let (data, w, h) = await CaptureService.downloadImage(url: imageURL) {
                    let image = ItemImage(data: data, source: "og", isPrimary: true, width: w, height: h)
                    context.insert(image)
                    image.item = item
                }
                if let extracted = CaptureService.extractText(html: page.html), !extracted.isEmpty {
                    item.extractedText = extracted
                    item.updatedAt = .now
                }
            } else {
                refetchError = "page re-fetch failed: unable to fetch page"
            }
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
}
