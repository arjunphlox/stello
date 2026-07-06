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

        for text in result.snippets {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
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
        enricher: Enricher
    ) async {
        guard item.enrichmentStatus == "text_done" else { return }

        do {
            guard enricher.isAvailable else {
                try markTerminalWithoutAI(item: item, context: context)
                return
            }

            let coverData = item.images?.first(where: \.isPrimary)?.data
                ?? item.images?.first?.data

            let result = try await enricher.enrich(
                title: item.title,
                summary: item.summary,
                domain: item.domain,
                coverImageData: coverData
            )
            try apply(result, to: item, context: context)
        } catch EnricherError.unavailable {
            try? markTerminalWithoutAI(item: item, context: context)
        } catch {
            item.enrichmentError = error.localizedDescription
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
        item.updatedAt = .now
        try context.save()
    }
}
