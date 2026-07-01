import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Validation

enum DropImportValidation {
    enum Kind: Equatable {
        case image
        case video
        case markdown
        case plainText
    }

    enum Rejection: Equatable, Error {
        case unsupportedType
        case videoTooLarge(bytes: Int)
        case textTooLong(characters: Int)
        case readFailed
    }

    static let maxVideoBytes = 50 * 1024 * 1024
    static let maxTextCharacters = 5000

    static let acceptedImageExtensions: Set<String> = ["png", "jpeg", "jpg", "heic", "webp", "gif"]
    static let acceptedVideoExtensions: Set<String> = ["mp4", "mov"]

    static func classify(url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if acceptedImageExtensions.contains(ext) { return .image }
        if acceptedVideoExtensions.contains(ext) { return .video }
        if ext == "md" { return .markdown }
        if ext == "txt" { return .plainText }
        return nil
    }

    static func validateFile(at url: URL, kind: Kind) -> Result<Void, Rejection> {
        switch kind {
        case .image:
            return .success(())
        case .video:
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else {
                return .failure(.readFailed)
            }
            if size > maxVideoBytes { return .failure(.videoTooLarge(bytes: size)) }
            return .success(())
        case .markdown, .plainText:
            guard let text = readText(from: url) else { return .failure(.readFailed) }
            if text.count > maxTextCharacters { return .failure(.textTooLong(characters: text.count)) }
            return .success(())
        }
    }

    static func readText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }
}

// MARK: - DropImportService

@MainActor
enum DropImportService {

    /// UTTypes accepted for window / app-icon import (new item).
    static var windowDropTypes: [UTType] {
        [.fileURL, .image, .movie, .plainText, markdownUTType].compactMap { $0 }
    }

    /// UTTypes accepted for attach-to-item drops (no video).
    static var attachDropTypes: [UTType] {
        [.fileURL, .image, .plainText, markdownUTType].compactMap { $0 }
    }

    private static var markdownUTType: UTType? {
        UTType("net.daringfireball.markdown") ?? .markdown
    }

    // MARK: - Public entry points

    /// Handle Dock icon / Open With / `.onOpenURL`.
    static func importFileURL(
        _ url: URL,
        context: ModelContext,
        coordinator: EnrichmentCoordinator
    ) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let kind = DropImportValidation.classify(url: url) else {
            logReject("unsupported open URL: \(url.lastPathComponent)")
            return
        }
        guard case .success = DropImportValidation.validateFile(at: url, kind: kind) else {
            logReject("open URL failed validation: \(url.lastPathComponent)")
            return
        }
        do {
            let item = try importFile(at: url, kind: kind, context: context)
            scheduleEnrichmentIfNeeded(for: item, kind: kind, coordinator: coordinator, context: context)
        } catch {
            logReject("importFileURL failed: \(error.localizedDescription)")
        }
    }

    /// Window drop — creates a new item per accepted file.
    @discardableResult
    static func importAsNewItem(
        from providers: [NSItemProvider],
        context: ModelContext,
        coordinator: EnrichmentCoordinator
    ) -> Bool {
        Task {
            for provider in providers {
                guard let url = await loadFileURL(from: provider) else { continue }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let kind = DropImportValidation.classify(url: url) else {
                    logReject("unsupported drop: \(url.lastPathComponent)")
                    continue
                }
                guard case .success = DropImportValidation.validateFile(at: url, kind: kind) else {
                    logReject("drop failed validation: \(url.lastPathComponent)")
                    continue
                }
                do {
                    let item = try importFile(at: url, kind: kind, context: context)
                    scheduleEnrichmentIfNeeded(for: item, kind: kind, coordinator: coordinator, context: context)
                } catch {
                    logReject("import failed: \(error.localizedDescription)")
                }
            }
        }
        return true
    }

    /// Card / panel drop — attach image or text snippet to an existing item.
    @discardableResult
    static func attachToItem(
        _ item: Item,
        from providers: [NSItemProvider],
        context: ModelContext
    ) -> Bool {
        Task {
            for provider in providers {
                guard let url = await loadFileURL(from: provider) else { continue }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let kind = DropImportValidation.classify(url: url) else {
                    logReject("unsupported attach: \(url.lastPathComponent)")
                    continue
                }
                guard kind != .video else {
                    logReject("video attach not supported on cards/panels")
                    continue
                }
                guard case .success = DropImportValidation.validateFile(at: url, kind: kind) else {
                    logReject("attach failed validation: \(url.lastPathComponent)")
                    continue
                }
                do {
                    try attachFile(at: url, kind: kind, to: item, context: context)
                } catch {
                    logReject("attach failed: \(error.localizedDescription)")
                }
            }
        }
        return true
    }

    // MARK: - Import (new item)

    private static func importFile(
        at url: URL,
        kind: DropImportValidation.Kind,
        context: ModelContext
    ) throws -> Item {
        let baseTitle = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let title = baseTitle.isEmpty ? "Dropped file" : baseTitle
        let slug = CaptureService.makeSlug(from: title, context: context)

        let item = Item(
            slug: slug,
            title: title,
            sourceURL: nil,
            needsReview: true,
            addedAt: .now,
            enrichmentStatus: "text_done"
        )
        context.insert(item)

        switch kind {
        case .image:
            let data = try Data(contentsOf: url)
            let (w, h) = CaptureService.imageDimensions(data: data)
            let img = ItemImage(data: data, source: "dropped", isPrimary: true, width: w, height: h)
            context.insert(img)
            img.item = item
            item.images = [img]

        case .video:
            let destPath = try storeVideoLocally(from: url)
            let attachment = LocalAttachment(localPath: destPath, mediaType: "video", fileName: url.lastPathComponent)
            context.insert(attachment)
            attachment.item = item
            item.attachments = [attachment]
            // Placeholder shell — no bytes in SwiftData; label drives "video" chip in UI.
            let placeholder = ItemImage(source: "dropped", isPrimary: true, label: "video")
            context.insert(placeholder)
            placeholder.item = item
            item.images = [placeholder]

        case .markdown:
            let text = DropImportValidation.readText(from: url) ?? ""
            item.bodyMarkdown = text
            item.summary = String(text.prefix(200))

        case .plainText:
            let text = DropImportValidation.readText(from: url) ?? ""
            item.summary = String(text.prefix(200))
            item.bodyMarkdown = text
        }

        let tagSpecs = RuleTagger.generateTags(title: title, description: item.summary, domain: nil)
        for spec in tagSpecs {
            let tag = Tag(name: spec.name, category: spec.category, weight: spec.weight)
            context.insert(tag)
            tag.item = item
        }

        try context.save()
        return item
    }

    // MARK: - Attach (existing item)

    private static func attachFile(
        at url: URL,
        kind: DropImportValidation.Kind,
        to item: Item,
        context: ModelContext
    ) throws {
        switch kind {
        case .image:
            let data = try Data(contentsOf: url)
            let (w, h) = CaptureService.imageDimensions(data: data)
            let needsPrimary = item.coverImage?.hasRenderableCoverData != true
            let img = ItemImage(data: data, source: "dropped", isPrimary: needsPrimary, width: w, height: h)
            context.insert(img)
            img.item = item
            if item.images == nil { item.images = [] }
            item.images?.append(img)

        case .markdown, .plainText:
            let text = DropImportValidation.readText(from: url) ?? ""
            let snippet = Snippet(text: text, source: "dropped")
            context.insert(snippet)
            snippet.item = item
            if item.snippets == nil { item.snippets = [] }
            item.snippets?.append(snippet)

        case .video:
            break // guarded at call site
        }

        item.updatedAt = .now
        try context.save()
    }

    // MARK: - Video local storage

    static func videosDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DropImportError.storageUnavailable
        }
        let dir = base.appendingPathComponent("Stello/videos", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func storeVideoLocally(from source: URL) throws -> String {
        let dir = try videosDirectory()
        let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension
        let dest = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest.path
    }

    // MARK: - Provider loading

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadTypedURL(from: provider, type: .fileURL)
        }
        // Some drags expose image/movie data directly — write to temp file.
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            guard let data = await loadData(from: provider, type: .image) else { return nil }
            return writeTemp(data: data, ext: "png")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await loadTypedURL(from: provider, type: .movie)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            guard let data = await loadData(from: provider, type: .plainText),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return writeTemp(text: text, ext: "txt")
        }
        if let md = markdownUTType,
           provider.hasItemConformingToTypeIdentifier(md.identifier) {
            guard let data = await loadData(from: provider, type: md),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return writeTemp(text: text, ext: "md")
        }
        return nil
    }

    private static func loadTypedURL(from provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: URL(string: str))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: data)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func writeTemp(data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func writeTemp(text: String, ext: String) -> URL? {
        writeTemp(data: Data(text.utf8), ext: ext)
    }

    // MARK: - Enrichment

    private static func scheduleEnrichmentIfNeeded(
        for item: Item,
        kind: DropImportValidation.Kind,
        coordinator: EnrichmentCoordinator,
        context: ModelContext
    ) {
        switch kind {
        case .markdown, .plainText:
            coordinator.scheduleEnrichment(for: item, context: context)
        case .image, .video:
            break
        }
    }

    private static func logReject(_ message: String) {
        #if DEBUG
        print("[DropImport] rejected: \(message)")
        #endif
    }
}

enum DropImportError: Error {
    case storageUnavailable
}
