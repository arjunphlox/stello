import SwiftUI
import SwiftData
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Image-forward masonry card mirroring the Stello web app: OG images with title/domain
/// overlays; text cards use a tinted block with the same overlay treatment.
struct ItemCardView: View {
    let item: Item
    var isSelected: Bool = false
    /// Concrete grid column count (auto or forced) — drives title scaling and overlay visibility.
    var resolvedColumns: Int = 2
    var onOpen: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    #if os(macOS)
    @State private var isHovered = false
    #endif
    @State private var isDropTargeted = false

    @State private var showMarkdownExporter = false
    @State private var showImageExporter = false
    @State private var showBundleExporter = false
    @State private var exportMarkdownText = ""
    @State private var exportImageData = Data()
    @State private var exportBundleData = Data()

    private static let visualCornerRadius: CGFloat = 6
    private static let selectionOutlineOffset: CGFloat = 4
    private static let hues: [Double] = [18, 80, 38, 140, 25, 45, 12, 100]
    private func stableHash(_ s: String) -> Int {
        s.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
    }

    private var coverHue: Double {
        Self.hues[abs(stableHash(item.slug)) % Self.hues.count] / 360.0
    }

    private var primaryImage: ItemImage? { item.coverImage }

    private var hasImage: Bool { item.hasRenderableCover }

    private var aspect: CGFloat {
        if let img = primaryImage, let w = img.width, let h = img.height, w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        return 1200.0 / 630.0
    }

    private var hasText: Bool {
        guard !hasImage else { return false }
        if item.hasVideoAttachment { return false }
        guard let s = item.summary else { return false }
        return s.count > 30 && !s.hasPrefix("Saved from")
    }

    private var isVideoCard: Bool {
        item.hasVideoAttachment || item.coverImage?.label == "video"
    }

    private var showCardOverlays: Bool { resolvedColumns <= 9 }

    private var scaledTitleSize: CGFloat {
        resolvedColumns <= 5 ? 16 : max(12, 16 - CGFloat(resolvedColumns - 5))
    }

    private var scaledPillSize: CGFloat {
        resolvedColumns <= 5 ? 11 : max(9, 11 - 0.5 * CGFloat(resolvedColumns - 5))
    }

    private var coverImageData: Data? { item.coverImage?.data }

    private var sourceURL: URL? {
        guard let urlString = item.sourceURL, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    private var exportBaseName: String {
        let base = item.slug.isEmpty ? item.title : item.slug
        let sanitized = base
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "item" : sanitized
    }

    private var dominantColor: Color? {
        let colorTags = (item.tags ?? [])
            .filter { $0.category == "color" }
            .sorted { $0.weight > $1.weight }
        for t in colorTags { if let c = Self.namedColor(t.name) { return c } }
        return nil
    }

    var body: some View {
        cardContent
            .clipShape(RoundedRectangle(cornerRadius: Self.visualCornerRadius, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Self.visualCornerRadius, style: .continuous)
                        .stroke(theme.accentColor, lineWidth: 1)
                        .padding(-Self.selectionOutlineOffset)
                } else if isDropTargeted {
                    RoundedRectangle(cornerRadius: Self.visualCornerRadius, style: .continuous)
                        .stroke(theme.accentColor.opacity(0.85), lineWidth: 2)
                        .padding(-2)
                }
            }
            .onDrop(of: DropImportService.attachDropTypes, isTargeted: $isDropTargeted) { providers in
                DropImportService.attachToItem(item, from: providers, context: context)
            }
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
            #if os(iOS)
            .contextMenu(menuItems: { cardContextMenu }, preview: { cardPreview })
            #else
            .contextMenu { cardContextMenu }
            #endif
            .fileExporter(
                isPresented: $showMarkdownExporter,
                document: MarkdownExportDocument(text: exportMarkdownText),
                contentType: .plainText,
                defaultFilename: "\(exportBaseName).md"
            ) { _ in }
            .fileExporter(
                isPresented: $showImageExporter,
                document: ImageExportDocument(data: exportImageData),
                contentType: Self.imageExportType(for: exportImageData),
                defaultFilename: "\(exportBaseName).\(Self.imageExportExtension(for: exportImageData))"
            ) { _ in }
            .fileExporter(
                isPresented: $showBundleExporter,
                document: ZipExportDocument(data: exportBundleData),
                contentType: .zip,
                defaultFilename: "\(exportBaseName).zip"
            ) { _ in }
    }

    @ViewBuilder private var cardContent: some View {
        if hasImage, let data = primaryImage?.data, let img = Self.platformImage(data) {
            imageCard(img)
        } else if isVideoCard {
            videoCard
        } else if hasText {
            textCard
        } else {
            placeholderCard
        }
    }

    private func imageCard(_ img: Image) -> some View {
        hoverDim(
            img
                .resizable()
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
        )
        .overlay(alignment: .bottomTrailing) {
            if showCardOverlays {
                domainPill.padding(10)
            }
        }
        .overlay(alignment: .topLeading) {
            #if os(macOS)
            if showCardOverlays {
                macTitleBadge
            }
            #endif
        }
    }

    private var videoCard: some View {
        hoverDim(
            ZStack {
                placeholderGradient
                VStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 28, weight: .light))
                    Text("Video")
                        .font(.karst(.subheadline, weight: .medium))
                }
                .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        )
        .overlay(alignment: .bottomTrailing) {
            if showCardOverlays {
                domainPill.padding(10)
            }
        }
        .overlay(alignment: .topLeading) {
            #if os(macOS)
            if showCardOverlays {
                macTitleBadge
            }
            #endif
        }
    }

    private var textCard: some View {
        hoverDim(
            Color(hue: coverHue,
                  saturation: theme.mode == .dark ? 0.15 : 0.12,
                  brightness: theme.mode == .dark ? 0.14 : 0.92)
            .frame(maxWidth: .infinity, minHeight: 140)
        )
        .overlay(alignment: .bottomTrailing) {
            if showCardOverlays {
                domainPill.padding(10)
            }
        }
        .overlay(alignment: .topLeading) {
            #if os(macOS)
            if showCardOverlays {
                macTitleBadge
            }
            #endif
        }
    }

    private var placeholderCard: some View {
        hoverDim(
            ZStack {
                placeholderGradient
                Text(String(item.title.first ?? "?").uppercased())
                    .font(.karst(size: 46, weight: .light))
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(height: 140)
        )
        .overlay(alignment: .bottomTrailing) {
            if showCardOverlays {
                domainPill.padding(10)
            }
        }
        .overlay(alignment: .topLeading) {
            #if os(macOS)
            if showCardOverlays {
                macTitleBadge
            }
            #endif
        }
    }

    private var placeholderGradient: some View {
        let hash = abs(stableHash(item.slug))
        let hueShift = Double(hash % 360) / 360.0
        return LinearGradient(
            colors: [
                Color(hue: (coverHue + hueShift).truncatingRemainder(dividingBy: 1),
                      saturation: theme.mode == .dark ? 0.28 : 0.18,
                      brightness: theme.mode == .dark ? 0.32 : 0.88),
                Color(hue: (coverHue + hueShift + 0.08).truncatingRemainder(dividingBy: 1),
                      saturation: theme.mode == .dark ? 0.22 : 0.14,
                      brightness: theme.mode == .dark ? 0.14 : 0.78),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    #if os(iOS)
    private var previewWidth: CGFloat {
        min(UIScreen.main.bounds.width - 32, 380)
    }

    @ViewBuilder private var cardPreview: some View {
        cardPreviewBody
            .frame(width: previewWidth)
            .clipShape(RoundedRectangle(cornerRadius: Self.visualCornerRadius, style: .continuous))
    }

    @ViewBuilder private var cardPreviewBody: some View {
        if hasImage, let data = primaryImage?.data, let img = Self.platformImage(data) {
            img
                .resizable()
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(alignment: .top) { previewTitleOverlay }
                .overlay(alignment: .bottomTrailing) { domainPill.padding(10) }
        } else if hasText {
            Color(hue: coverHue,
                  saturation: theme.mode == .dark ? 0.15 : 0.12,
                  brightness: theme.mode == .dark ? 0.14 : 0.92)
            .frame(maxWidth: .infinity, minHeight: 140)
            .overlay(alignment: .top) { previewTitleOverlay }
            .overlay(alignment: .bottomTrailing) { domainPill.padding(10) }
        } else {
            ZStack {
                placeholderGradient
                Text(String(item.title.first ?? "?").uppercased())
                    .font(.karst(size: 46, weight: .light))
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(height: 140)
            .overlay(alignment: .top) { previewTitleOverlay }
            .overlay(alignment: .bottomTrailing) { domainPill.padding(10) }
        }
    }

    @ViewBuilder private var previewTitleOverlay: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [.black.opacity(0.82), .black.opacity(0.45), .black.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 96)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)

            if !item.title.isEmpty {
                Text(item.title)
                    .font(.karst(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .padding(10)
            }
        }
    }
    #endif

    #if os(macOS)
    @ViewBuilder private var macTitleBadge: some View {
        if !item.title.isEmpty {
            Text(item.title)
                .font(.karst(size: scaledTitleSize, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .padding(.bottom, 40)
                .opacity(isHovered ? 1 : 0)
                .offset(y: isHovered ? 0 : -4)
                .animation(.easeOut(duration: 0.18), value: isHovered)
                .allowsHitTesting(false)
        }
    }
    #endif

    @ViewBuilder private var domainPill: some View {
        let label = item.displayLink
        if !label.isEmpty {
            let tint = dominantColor ?? .white
            Text(label)
                .font(.karst(size: scaledPillSize, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.22))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private func hoverDim<Content: View>(_ content: Content) -> some View {
        #if os(macOS)
        content
            .colorMultiply(isHovered ? Color(white: 0.175) : .white)
            .animation(.easeOut(duration: 0.18), value: isHovered)
        #else
        content
        #endif
    }

    // MARK: - Context menu

    @ViewBuilder private var cardContextMenu: some View {
        if let onOpen {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right")
            }
        }

        Button {
            enrichmentCoordinator.scheduleEnrichment(for: item, context: context)
        } label: {
            Label("Enrich", systemImage: "sparkles")
        }

        if let url = sourceURL {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                copyText(url.absoluteString)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }

        Menu {
            Button {
                copyText(item.title)
            } label: {
                Label("Copy Title", systemImage: "textformat")
            }
            Button {
                copyText(markdownExport())
            } label: {
                Label("Copy Details (Markdown)", systemImage: "doc.text")
            }
            if let data = coverImageData {
                Button {
                    copyImage(data)
                } label: {
                    Label("Copy Image", systemImage: "photo")
                }
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Menu {
            Button {
                exportMarkdownText = markdownExport()
                showMarkdownExporter = true
            } label: {
                Label("Download Markdown", systemImage: "doc.text")
            }
            if let data = coverImageData {
                Button {
                    exportImageData = data
                    showImageExporter = true
                } label: {
                    Label("Download Image", systemImage: "photo")
                }
            }
            Button {
                beginFullItemExport()
            } label: {
                Label("Download Full Item", systemImage: "shippingbox")
            }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }

        Divider()

        Button(role: .destructive, action: deleteItem) {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteItem() {
        context.delete(item)
        try? context.save()
    }

    private func beginFullItemExport() {
        do {
            exportBundleData = try ItemBundleExporter.createBundleZip(
                exportName: exportBaseName,
                markdown: markdownExport(),
                images: item.images ?? [],
                snippets: item.snippets ?? [],
                videoAttachments: item.attachments ?? []
            )
            showBundleExporter = true
        } catch {
            // Bundle assembly failed — skip presenting an empty exporter.
        }
    }

    private func markdownExport() -> String {
        var lines: [String] = []

        if !item.title.isEmpty {
            lines.append("# \(item.title)")
            lines.append("")
        }

        if let summary = item.summary, !summary.isEmpty {
            lines.append(summary)
            lines.append("")
        }

        var metadata: [String] = []
        if let url = item.sourceURL, !url.isEmpty {
            metadata.append("- **URL:** \(url)")
        }
        if let domain = item.domain, !domain.isEmpty {
            metadata.append("- **Domain:** \(domain)")
        }
        metadata.append("- **Saved:** \(Self.exportDateFormatter.string(from: item.addedAt))")

        let tagNames = (item.tags ?? [])
            .map(\.name)
            .filter { !$0.isEmpty }
        if !tagNames.isEmpty {
            metadata.append("- **Tags:** \(tagNames.joined(separator: ", "))")
        }

        if !metadata.isEmpty {
            lines.append(contentsOf: metadata)
            lines.append("")
        }

        let snippets = (item.snippets ?? []).filter { !$0.text.isEmpty }
        if !snippets.isEmpty {
            lines.append("## Notes")
            lines.append("")
            for snippet in snippets {
                lines.append("- \(snippet.text)")
            }
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func copyImage(_ data: Data) {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #else
        guard let image = UIImage(data: data) else { return }
        UIPasteboard.general.image = image
        #endif
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static func imageExportType(for data: Data) -> UTType {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        return .png
    }

    private static func imageExportExtension(for data: Data) -> String {
        imageExportType(for: data) == .jpeg ? "jpg" : "png"
    }

    // MARK: - Helpers

    static func platformImage(_ data: Data) -> Image? {
        #if os(macOS)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #else
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        #if os(macOS)
        return Image(decorative: cg, scale: 2, orientation: .up)
        #else
        return Image(uiImage: UIImage(cgImage: cg))
        #endif
    }

    static func namedColor(_ name: String) -> Color? {
        switch name.lowercased() {
        case "red":                      return Color(hex: "#e5484d")
        case "coral":                    return Color(hex: "#e5664d")
        case "orange":                   return Color(hex: "#f76b15")
        case "amber", "gold":            return Color(hex: "#ffc53d")
        case "mustard":                  return Color(hex: "#d6a417")
        case "yellow":                   return Color(hex: "#f5d90a")
        case "lime":                     return Color(hex: "#bdee63")
        case "green":                    return Color(hex: "#46a758")
        case "sage":                     return Color(hex: "#8aa37b")
        case "mint":                     return Color(hex: "#86ead4")
        case "teal":                     return Color(hex: "#12a594")
        case "cyan":                     return Color(hex: "#00a2c7")
        case "blue":                     return Color(hex: "#3e63dd")
        case "navy":                     return Color(hex: "#273e89")
        case "slate", "slate-blue":      return Color(hex: "#5a7596")
        case "indigo", "iris":           return Color(hex: "#5b5bd6")
        case "purple", "violet":         return Color(hex: "#8e4ec6")
        case "mauve":                    return Color(hex: "#b58392")
        case "magenta", "pink":          return Color(hex: "#d6409f")
        case "blush":                    return Color(hex: "#e093b6")
        case "brown":                    return Color(hex: "#ad7f58")
        case "tan", "beige":             return Color(hex: "#c9aa7e")
        case "cream", "ivory":           return Color(hex: "#e9e2cf")
        case "terracotta":               return Color(hex: "#c4623d")
        case "burgundy", "maroon":       return Color(hex: "#8b2f3b")
        case "olive":                    return Color(hex: "#6b6f30")
        case "charcoal":                 return Color(hex: "#3b3a37")
        case "gray", "grey", "neutral":  return Color(hex: "#8d8d86")
        case "white":                    return Color(hex: "#e8e8e6")
        case "black":                    return Color(hex: "#1a1a17")
        default:                         return nil
        }
    }
}

// MARK: - Export documents

private struct MarkdownExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct ImageExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .jpeg, .data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        if let contents = configuration.file.regularFileContents {
            data = contents
        } else {
            data = Data()
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ZipExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        if let contents = configuration.file.regularFileContents {
            data = contents
        } else {
            data = Data()
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ItemCardView(item: SeedData.sampleItem)
        .frame(width: 220)
        .padding()
        .background(Color(hex: "#111110"))
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}
