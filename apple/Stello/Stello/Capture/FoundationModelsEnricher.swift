import CoreGraphics
import Foundation
import ImageIO
import FoundationModels

struct FoundationModelsEnricher: Enricher {
    private let model: SystemLanguageModel

    /// Whether the OS's FoundationModels actually contains the image `Attachment` API.
    ///
    /// History (full story: docs/memory/project_native_apple_app.md, build-harness section):
    /// building with the Xcode 27 BETA 2 SDK against macOS 27 beta 3 (26A5378j) bound the
    /// vision call to an attachment spelling the OS doesn't export → weak-symbol call →
    /// SIGSEGV at EnrichmentPrompts.swift:261. The OS *does* ship image attachments
    /// (`Prompt.Attachment` + `ImageAttachmentContent` per dyld_info), so this is SDK/OS
    /// beta skew, not a missing feature. True requires building with a matched toolchain
    /// (Xcode beta 3+ on macOS beta 3+). If the crash ever recurs after a toolchain/OS
    /// drift, set false — text jobs (snippets/why-saved) are unaffected by this flag.
    nonisolated static let imageAttachmentSupported = true

    nonisolated init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    var isAvailable: Bool {
        switch model.availability {
        case .available: return true
        case .unavailable: return false
        }
    }

    /// Human-readable reason when the system model is unavailable (nil when available) —
    /// surfaced on the item so a forced Enrich never silently no-ops.
    var unavailableReason: String? {
        switch model.availability {
        case .available: return nil
        case .unavailable(let reason): return String(describing: reason)
        }
    }

    func enrich(
        title: String,
        summary: String?,
        domain: String?,
        coverImageData: Data?,
        pageText: String? = nil
    ) async throws -> EnrichmentResult {
        guard isAvailable else { throw EnricherError.unavailable }

        var visionTags: [VisionTagSpec] = []
        var snippets: [String] = []
        var whySavedSuggestions: [String] = []
        // Per-job failures are tolerated (partial results beat none), but collected so a
        // TOTAL failure can throw with the reason instead of silently returning nothing.
        var jobErrors: [String] = []

        if Self.imageAttachmentSupported,
           let coverImageData, let coverCGImage = Self.cgImage(from: coverImageData) {
            do {
                let tags = try await EnrichmentRunner.enrichVision(cover: coverCGImage)
                visionTags = Self.mapVisionTags(tags)
            } catch {
                jobErrors.append("vision: \(error.localizedDescription)")
            }
        }

        if let pageText = Self.pageText(title: title, summary: summary, extractedText: pageText) {
            do {
                snippets = try await EnrichmentRunner.enrichSnippets(pageText: pageText)
            } catch {
                jobErrors.append("snippets: \(error.localizedDescription)")
            }

            do {
                whySavedSuggestions = try await EnrichmentRunner.enrichWhySaved(pageText: pageText)
            } catch {
                jobErrors.append("why-saved: \(error.localizedDescription)")
            }
        } else {
            jobErrors.append("no page text: item has an empty title and summary")
        }

        if visionTags.isEmpty && snippets.isEmpty && whySavedSuggestions.isEmpty,
           let first = jobErrors.first {
            let suffix = jobErrors.count > 1 ? " (+\(jobErrors.count - 1) more)" : ""
            throw EnricherError.allJobsFailed(first + suffix)
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

    /// Prefers the richer `extractedText` (readability-lite page text, capped for the
    /// prompt) when present; falls back to the thin title+summary the model previously saw.
    private static func pageText(title: String, summary: String?, extractedText: String?) -> String? {
        if let extractedText {
            let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(trimmed.prefix(3_000)) }
        }

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
