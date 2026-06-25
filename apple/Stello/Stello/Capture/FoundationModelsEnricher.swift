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

        let session = LanguageModelSession(
            model: model,
            instructions: EnrichmentPrompts.systemInstructions
        )

        let promptText = EnrichmentPrompts.userPrompt(title: title, summary: summary, domain: domain)
        let coverCGImage = coverImageData.flatMap { Self.cgImage(from: $0) }

        let response: LanguageModelSession.Response<EnrichmentGenerableResult>
        if let coverCGImage {
            response = try await session.respond(
                generating: EnrichmentGenerableResult.self,
                prompt: {
                    promptText
                    Attachment(coverCGImage)
                }
            )
        } else {
            response = try await session.respond(
                to: promptText,
                generating: EnrichmentGenerableResult.self
            )
        }

        return Self.map(response.content)
    }

  // MARK: - Mapping

    private static func map(_ generated: EnrichmentGenerableResult) -> EnrichmentResult {
        var visionTags: [VisionTagSpec] = []
        for t in generated.colorTags {
            visionTags.append(VisionTagSpec(name: t.name, category: "color", weight: clampWeight(t.weight)))
        }
        for t in generated.styleTags {
            visionTags.append(VisionTagSpec(name: t.name, category: "style", weight: clampWeight(t.weight)))
        }
        for t in generated.moodTags {
            visionTags.append(VisionTagSpec(name: t.name, category: "mood", weight: clampWeight(t.weight)))
        }

        let snippets = generated.snippets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 400 }
            .prefix(5)
            .map { String($0) }

        let reasons = generated.whySavedSuggestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { String($0) }

        return EnrichmentResult(
            visionTags: visionTags,
            snippets: snippets,
            whySavedSuggestions: reasons
        )
    }

    private static func clampWeight(_ w: Double) -> Double {
        min(1.0, max(0.0, w))
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
