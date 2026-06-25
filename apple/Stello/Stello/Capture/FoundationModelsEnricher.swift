import CoreGraphics
import Foundation
import ImageIO
import FoundationModels

struct FoundationModelsEnricher: Enricher {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    var isAvailable: Bool {
        switch model.availability {
        case .available: return true
        case .unavailable: return false
        }
    }

    func enrich(
        title: String,
        summary: String?,
        domain: String?,
        coverImageData: Data?
    ) async throws -> EnrichmentResult {
        guard isAvailable else { throw EnricherError.unavailable }

        var visionTags: [VisionTagSpec] = []
        var snippets: [String] = []
        var whySavedSuggestions: [String] = []

        if let coverImageData, let coverCGImage = Self.cgImage(from: coverImageData) {
            do {
                let tags = try await EnrichmentRunner.enrichVision(cover: coverCGImage)
                visionTags = Self.mapVisionTags(tags)
            } catch {
                // Per-job failure: keep empty visionTags, continue with text jobs.
            }
        }

        if let pageText = Self.pageText(title: title, summary: summary) {
            do {
                snippets = try await EnrichmentRunner.enrichSnippets(pageText: pageText)
            } catch {
                // Per-job failure tolerated.
            }

            do {
                whySavedSuggestions = try await EnrichmentRunner.enrichWhySaved(pageText: pageText)
            } catch {
                // Per-job failure tolerated.
            }
        }

        return EnrichmentResult(
            visionTags: visionTags,
            snippets: snippets,
            whySavedSuggestions: whySavedSuggestions
        )
    }

    // MARK: - Mapping

    static func mapVisionTags(_ tags: VisionTags) -> [VisionTagSpec] {
        var specs: [VisionTagSpec] = []
        for t in tags.color {
            specs.append(VisionTagSpec(name: t.tag, category: "color", weight: t.weight))
        }
        for t in tags.style {
            specs.append(VisionTagSpec(name: t.tag, category: "style", weight: t.weight))
        }
        for t in tags.mood {
            specs.append(VisionTagSpec(name: t.tag, category: "mood", weight: t.weight))
        }
        return specs
    }

    private static func pageText(title: String, summary: String?) -> String? {
        let titleTrimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryTrimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if titleTrimmed.isEmpty && summaryTrimmed.isEmpty { return nil }
        if summaryTrimmed.isEmpty { return titleTrimmed }
        if titleTrimmed.isEmpty { return summaryTrimmed }
        return "\(titleTrimmed)\n\n\(summaryTrimmed)"
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
