import Foundation

/// Builds a ZIP bundle of an item's markdown, snippets, images, and local video attachments.
enum ItemBundleExporter {

    enum ExportError: Error {
        case zipFailed
    }

    static func createBundleZip(
        exportName: String,
        markdown: String,
        images: [ItemImage],
        snippets: [Snippet],
        videoAttachments: [LocalAttachment]
    ) throws -> Data {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory
            .appendingPathComponent("stello-export-\(UUID().uuidString)", isDirectory: true)
        let bundleFolder = tempRoot.appendingPathComponent(exportName, isDirectory: true)

        defer {
            try? fm.removeItem(at: tempRoot)
        }

        try fm.createDirectory(at: bundleFolder, withIntermediateDirectories: true)

        let mdURL = bundleFolder.appendingPathComponent("\(exportName).md")
        try markdown.write(to: mdURL, atomically: true, encoding: .utf8)

        let nonEmptySnippets = snippets.filter { !$0.text.isEmpty }
        if !nonEmptySnippets.isEmpty {
            let snippetsDir = bundleFolder.appendingPathComponent("snippets", isDirectory: true)
            try fm.createDirectory(at: snippetsDir, withIntermediateDirectories: true)
            for (index, snippet) in nonEmptySnippets.enumerated() {
                let snippetURL = snippetsDir.appendingPathComponent("snippet-\(index + 1).txt")
                try snippet.text.write(to: snippetURL, atomically: true, encoding: .utf8)
            }
        }

        let imagesWithData = images.compactMap { image -> Data? in
            guard let data = image.data, !data.isEmpty else { return nil }
            return data
        }
        if !imagesWithData.isEmpty {
            let imagesDir = bundleFolder.appendingPathComponent("images", isDirectory: true)
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for (index, data) in imagesWithData.enumerated() {
                let ext = imageExtension(for: data)
                let imageURL = imagesDir.appendingPathComponent("image-\(index + 1).\(ext)")
                try data.write(to: imageURL)
            }
        }

        let videos = videoAttachments.filter { $0.mediaType == "video" }
        if !videos.isEmpty {
            let videosDir = bundleFolder.appendingPathComponent("videos", isDirectory: true)
            try fm.createDirectory(at: videosDir, withIntermediateDirectories: true)
            for attachment in videos {
                let sourceURL = URL(fileURLWithPath: attachment.localPath)
                guard fm.fileExists(atPath: sourceURL.path) else { continue }
                let destName = attachment.fileName ?? sourceURL.lastPathComponent
                let destURL = videosDir.appendingPathComponent(destName)
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: sourceURL, to: destURL)
            }
        }

        return try zipDirectory(at: bundleFolder)
    }

    static func imageExtension(for data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.count >= 12,
           data.starts(with: [0x52, 0x49, 0x46, 0x46]),
           String(data: data[8..<12], encoding: .ascii) == "WEBP" {
            return "webp"
        }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        return "bin"
    }

    private static func zipDirectory(at folderURL: URL) throws -> Data {
        var coordinatorError: NSError?
        var zipData: Data?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(
            readingItemAt: folderURL,
            options: [.forUploading],
            error: &coordinatorError
        ) { zippedURL in
            zipData = try? Data(contentsOf: zippedURL)
        }

        if let coordinatorError { throw coordinatorError }
        guard let zipData, !zipData.isEmpty else { throw ExportError.zipFailed }
        return zipData
    }
}
