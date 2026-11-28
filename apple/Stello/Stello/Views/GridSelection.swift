import SwiftUI
import SwiftData
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if os(iOS)
import SafariServices
#endif

// MARK: - Selection

/// Items picked in the grid for bulk actions (web `GridSelect` in app.js).
///
/// Mac: drag a box across the grid, ⌘-click, ⇧-click. iPad / iPhone: press and hold a
/// card, then Select; while selecting, a tap adds or removes a card. The selection bar
/// takes the bottom bar's place; a selected card's menu acts on all of them.
@MainActor @Observable
final class GridSelection {
    static let shared = GridSelection()

    private(set) var ids: Set<UUID> = []
    /// Bumped on every change: part of the grid's card token, so only on-screen cards redraw.
    private(set) var version: UInt = 0
    /// The grid's items in display order (filters and search applied). The grid keeps it
    /// current; select all, ranges and pruning read it.
    @ObservationIgnored var shownItems: [Item] = []
    @ObservationIgnored private var anchor: UUID?
    /// Loads the rest of the library (the grid starts with the newest weeks).
    @ObservationIgnored var loadAll: (() -> Void)?
    /// Select All was asked for before the whole library was loaded: keep it all
    /// selected as the rest streams in, until the selection is changed by hand.
    @ObservationIgnored private var wantsAll = false

    var showTagEditor = false
    var confirmDelete = false
    /// A short line shown over the selection bar ("Copied 12 links").
    var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    var isActive: Bool { !ids.isEmpty }
    var count: Int { ids.count }
    func contains(_ item: Item) -> Bool { ids.contains(item.id) }

    /// The selected items, in grid order.
    var items: [Item] { shownItems.filter { ids.contains($0.id) } }

    var allSelected: Bool {
        !shownItems.isEmpty && ids.count >= shownItems.count && shownItems.allSatisfy { ids.contains($0.id) }
    }

    func toggle(_ item: Item) {
        wantsAll = false
        if ids.contains(item.id) { ids.remove(item.id) } else { ids.insert(item.id) }
        anchor = item.id
        bump()
    }

    /// ⇧-click: everything between the last clicked card and this one, in grid order.
    func extend(to item: Item) {
        let order = shownItems.map(\.id)
        guard let anchor, let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: item.id) else {
            toggle(item)
            return
        }
        var next = ids
        for id in order[min(a, b)...max(a, b)] { next.insert(id) }
        set(next)
        self.anchor = item.id
    }

    func set(_ next: Set<UUID>) {
        guard next != ids else { return }
        ids = next
        bump()
    }

    func selectAll() {
        wantsAll = true
        loadAll?()
        set(Set(shownItems.map(\.id)))
    }

    /// The grid's items changed (filters, search, more loaded, deletes).
    func gridChanged(_ items: [Item]) {
        shownItems = items
        if wantsAll, isActive { set(Set(items.map(\.id))) } else { prune() }
    }

    func clear() {
        guard isActive else { return }
        ids = []
        anchor = nil
        wantsAll = false
        showTagEditor = false
        confirmDelete = false
        bump()
    }

    /// Drop what the grid no longer shows (filters, search, deletes).
    func prune() {
        guard isActive else { return }
        let shown = Set(shownItems.map(\.id))
        let kept = ids.intersection(shown)
        if kept != ids { ids = kept; bump() }
    }

    func say(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private func bump() { version &+= 1 }
}

// MARK: - Actions

/// One tag across the selection: on how many of the selected items it sits.
nonisolated struct SelectionTag: Identifiable, Hashable, Sendable {
    let name: String
    let category: String
    let count: Int
    var id: String { "\(category):\(name)" }
}

@MainActor
enum BulkActions {
    static func links(_ items: [Item]) -> [URL] {
        items.compactMap { item in
            guard let s = item.sourceURL, let url = URL(string: s),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return url
        }
    }

    #if os(macOS)
    /// Every link as a tab in the default browser.
    static func openLinks(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let probe = URL(string: "https://example.com"),
           let browser = NSWorkspace.shared.urlForApplication(toOpen: probe) {
            NSWorkspace.shared.open(urls, withApplicationAt: browser, configuration: config, completionHandler: nil)
        } else {
            urls.forEach { NSWorkspace.shared.open($0) }
        }
    }
    #endif

    #if os(iOS)
    /// iPhone / iPad can't open many Safari tabs at once; Reading List keeps them all.
    static func addToReadingList(_ items: [Item]) -> Int {
        guard let list = SSReadingList.default() else { return 0 }
        var added = 0
        for item in items {
            guard let s = item.sourceURL, let url = URL(string: s), SSReadingList.supportsURL(url) else { continue }
            if (try? list.addItem(with: url, title: item.title, previewText: item.summary)) != nil { added += 1 }
        }
        return added
    }
    #endif

    static func tags(on items: [Item]) -> [SelectionTag] {
        var counts: [String: (name: String, category: String, count: Int)] = [:]
        var order: [String] = []
        for item in items {
            for tag in item.tags where !tag.name.isEmpty && tag.category != "collection" {
                let key = "\(tag.category):\(tag.name)"
                if let c = counts[key] { counts[key] = (c.name, c.category, c.count + 1) }
                else { counts[key] = (tag.name, tag.category, 1); order.append(key) }
            }
        }
        return order.compactMap { counts[$0] }
            .map { SelectionTag(name: $0.name, category: $0.category, count: $0.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Adds the tag to every selected item that doesn't have it. Returns how many changed.
    static func addTag(_ raw: String, category: String, to items: [Item], context: ModelContext) -> Int {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty else { return 0 }
        let key = name.lowercased()
        var changed = 0
        for item in items where !item.tags.contains(where: { $0.name.lowercased() == key }) {
            item.tags.append(ItemTag(name: name, category: category, weight: 0.9, source: "manual"))
            item.updatedAt = .now
            changed += 1
        }
        if changed > 0 { try? context.save() }
        return changed
    }

    static func removeTag(_ tag: SelectionTag, from items: [Item], context: ModelContext) -> Int {
        var changed = 0
        for item in items where item.tags.contains(where: { $0.name == tag.name && $0.category == tag.category }) {
            item.tags.removeAll { $0.name == tag.name && $0.category == tag.category }
            item.updatedAt = .now
            changed += 1
        }
        if changed > 0 { try? context.save() }
        return changed
    }

    static func markReviewed(_ items: [Item], context: ModelContext) -> Int {
        let due = items.filter(AwaitingReviewFilter.isEligible)
        for item in due {
            item.needsReview = false
            item.updatedAt = .now
        }
        if !due.isEmpty { try? context.save() }
        return due.count
    }

    /// Deletes in SwiftData; the folder writer moves their files to the folder's .trash
    /// and sync tells the web app.
    static func delete(_ items: [Item], context: ModelContext) -> Int {
        for item in items { context.delete(item) }
        try? context.save()
        return items.count
    }

    static func addToCanvas(_ items: [Item]) -> Int {
        var heights: [String: CGFloat] = [:]
        for item in items {
            let img = item.coverImage
            heights[item.slug] = CanvasMetrics.cardHeight(
                imageWidth: img?.width, imageHeight: img?.height,
                hasImage: img?.hasRenderableCoverData == true)
        }
        let fallback = (CanvasMetrics.cardWidth * 0.62).rounded()
        return CanvasStore.shared.addMany(items.map(\.slug)) { heights[$0] ?? fallback }.count
    }

    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func copyLinks(_ items: [Item]) -> Int {
        let urls = links(items)
        guard !urls.isEmpty else { return 0 }
        copy(urls.map(\.absoluteString).joined(separator: "\n"))
        return urls.count
    }

    static func copyDetails(_ items: [Item]) {
        copy(items.map(ItemCardView.markdown(for:)).joined(separator: "\n\n---\n\n"))
    }

    /// One SVG with every cover laid out as a moodboard; Figma turns pasted SVG into
    /// layers, one group per item named after it (web `copyForFigma`).
    static func copyForFigma(_ items: [Item], selection: GridSelection) {
        let picked = Array(items.prefix(FigmaMoodboard.maxItems))
        let inputs = picked.map { item in
            FigmaMoodboard.Input(
                title: item.title, domain: item.domain ?? "",
                image: item.coverImage?.hasRenderableCoverData == true ? item.coverImage?.data : nil)
        }
        selection.say("Preparing \(picked.count == 1 ? "1 item" : "\(picked.count) items") for Figma…")
        let more = items.count > picked.count
        Task {
            let svg = await Task.detached(priority: .userInitiated) { FigmaMoodboard.svg(for: inputs) }.value
            copy(svg)
            selection.say(more ? "Copied the first \(FigmaMoodboard.maxItems). Paste in Figma."
                               : "Copied \(picked.count == 1 ? "1 item" : "\(picked.count) items"). Paste in Figma.")
        }
    }
}

// MARK: - Figma moodboard (pure, off the main thread)

nonisolated enum FigmaMoodboard {
    static let maxItems = 60
    static let cardWidth: CGFloat = 360
    static let gap: CGFloat = 24

    nonisolated struct Input: Sendable {
        var title: String
        var domain: String
        var image: Data?
    }

    nonisolated struct Placed: Equatable, Sendable {
        var x: CGFloat, y: CGFloat, height: CGFloat
    }

    /// Shortest-column packing, up to four columns (web `figmaSVG`).
    static func layout(aspects: [CGFloat?]) -> (placed: [Placed], width: CGFloat, height: CGFloat) {
        let columns = max(1, min(4, Int(Double(aspects.count).squareRoot().rounded(.up))))
        var tops = [CGFloat](repeating: 0, count: columns)
        var placed: [Placed] = []
        for aspect in aspects {
            var c = 0
            for i in 1..<max(columns, 1) where tops[i] < tops[c] { c = i }
            let h = aspect.map { (cardWidth / max($0, 0.05)).rounded() } ?? 200
            placed.append(Placed(x: CGFloat(c) * (cardWidth + gap), y: tops[c], height: h))
            tops[c] += h + gap
        }
        let width = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * gap
        return (placed, width, max((tops.max() ?? 0) - gap, 0))
    }

    static func svg(for inputs: [Input]) -> String {
        let images = inputs.map { $0.image.flatMap(jpeg) }
        let aspects: [CGFloat?] = images.map { img in img.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } }
        let (placed, width, height) = layout(aspects: aspects)
        var parts: [String] = []
        for (i, input) in inputs.enumerated() {
            let p = placed[i]
            let name = esc(String((input.title.isEmpty ? input.domain : input.title).prefix(120)))
            var inner: String
            if let img = images[i] {
                inner = "<image x=\"\(n(p.x))\" y=\"\(n(p.y))\" width=\"\(n(cardWidth))\" height=\"\(n(p.height))\" preserveAspectRatio=\"xMidYMid slice\" href=\"data:image/jpeg;base64,\(img.data.base64EncodedString())\"/>"
            } else {
                inner = "<rect x=\"\(n(p.x))\" y=\"\(n(p.y))\" width=\"\(n(cardWidth))\" height=\"\(n(p.height))\" rx=\"4\" fill=\"#1F1F1C\"/>"
                let lines = wrap(input.title.isEmpty ? input.domain : input.title, max: 30).prefix(4)
                inner += "<text x=\"\(n(p.x + 20))\" y=\"\(n(p.y + 40))\" fill=\"#F2F2EE\" font-family=\"Karst, Inter, sans-serif\" font-size=\"20\">"
                for (k, line) in lines.enumerated() {
                    inner += "<tspan x=\"\(n(p.x + 20))\" dy=\"\(k == 0 ? 0 : 26)\">\(esc(line))</tspan>"
                }
                inner += "</text>"
                if !input.domain.isEmpty {
                    inner += "<text x=\"\(n(p.x + 20))\" y=\"\(n(p.y + p.height - 20))\" fill=\"#8F8F8A\" font-family=\"Karst, Inter, sans-serif\" font-size=\"14\">\(esc(input.domain))</text>"
                }
            }
            parts.append("<g id=\"\(name)\">\(inner)</g>")
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"\(n(width))\" height=\"\(n(height))\" viewBox=\"0 0 \(n(width)) \(n(height))\">\(parts.joined())</svg>"
    }

    /// The cover as a JPEG of at most 1200 px on the long side (Figma's SVG import takes
    /// JPEG and PNG, not WebP or HEIC).
    static func jpeg(_ data: Data) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, image.width, image.height)
    }

    static func wrap(_ text: String, max: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            let next = line.isEmpty ? String(word) : line + " " + String(word)
            if next.count > max, !line.isEmpty { lines.append(line); line = String(word) } else { line = next }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func n(_ v: CGFloat) -> String { String(Int(v.rounded())) }
}

// MARK: - Menu (selected card's context menu + the bar's ⋯ button)

struct BulkMenuItems: View {
    let selection: GridSelection
    @Environment(\.modelContext) private var context

    var body: some View {
        let items = selection.items
        let links = BulkActions.links(items)
        Section("\(items.count) selected") {
            #if os(macOS)
            if !links.isEmpty {
                Button {
                    BulkActions.openLinks(links)
                } label: {
                    Label(links.count == 1 ? "Open Link" : "Open \(links.count) Links", systemImage: "arrow.up.right")
                }
            }
            #elseif os(iOS)
            if !links.isEmpty {
                Button {
                    let n = BulkActions.addToReadingList(items)
                    selection.say(n == 1 ? "Added 1 link to Reading List" : "Added \(n) links to Reading List")
                } label: {
                    Label("Add to Reading List", systemImage: "eyeglasses")
                }
            }
            #endif
            Button {
                let n = BulkActions.addToCanvas(items)
                selection.say(n == 0 ? "Already on the canvas" : (n == 1 ? "Added 1 item to the canvas" : "Added \(n) items to the canvas"))
            } label: {
                Label("Add to Canvas", systemImage: "plus.rectangle.on.rectangle")
            }
            Button {
                selection.showTagEditor = true
            } label: {
                Label("Edit Tags…", systemImage: "tag")
            }
            if items.contains(where: AwaitingReviewFilter.isEligible) {
                Button {
                    let n = BulkActions.markReviewed(items, context: context)
                    selection.say(n == 1 ? "Marked 1 item reviewed" : "Marked \(n) items reviewed")
                } label: {
                    Label("Mark Reviewed", systemImage: "eye")
                }
            }
        }
        Section {
            Button {
                BulkActions.copyForFigma(items, selection: selection)
            } label: {
                Label("Copy to Figma", systemImage: "square.on.square.dashed")
            }
            if !links.isEmpty {
                Button {
                    let n = BulkActions.copyLinks(items)
                    selection.say(n == 1 ? "Link copied" : "\(n) links copied")
                } label: {
                    Label(links.count == 1 ? "Copy Link" : "Copy Links", systemImage: "link")
                }
                ShareLink(items: links) {
                    Label("Share Links", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                BulkActions.copyDetails(items)
                selection.say("Details copied")
            } label: {
                Label("Copy Details (Markdown)", systemImage: "doc.text")
            }
        }
        Section {
            Button(role: .destructive) {
                selection.confirmDelete = true
            } label: {
                Label(items.count == 1 ? "Delete 1 Item" : "Delete \(items.count) Items", systemImage: "trash")
            }
        }
    }
}

// MARK: - Selection bar (takes the bottom bar's place)

struct GridSelectionBar: View {
    let selection: GridSelection
    var compactPhone: Bool = false

    @Environment(\.appTheme) private var theme

    private var diameter: CGFloat { StelloLayout.controlBarButtonDiameter(compactPhone: compactPhone) }
    private var symbol: CGFloat { StelloLayout.controlBarSymbolSize(compactPhone: compactPhone) }
    private var height: CGFloat { StelloLayout.controlBarHeight(compactPhone: compactPhone) }

    var body: some View {
        VStack(spacing: 10) {
            if let notice = selection.notice {
                Text(notice)
                    .font(.karst(size: 13))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: StelloLayout.controlBarSpacing) {
                StelloGlassIconButton(
                    systemName: "xmark", style: .controlBar,
                    controlBarDiameter: diameter, controlBarSymbolSize: symbol,
                    label: "Done", action: { withAnimation(.smooth(duration: 0.2)) { selection.clear() } }
                )
                .keyboardShortcut(.cancelAction)
                countPill
                Menu {
                    BulkMenuItems(selection: selection)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: symbol, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.88))
                        .frame(width: diameter, height: diameter)
                        .background { glass(Circle()) }
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Actions")
                .help("Actions")
                StelloGlassIconButton(
                    systemName: "trash", style: .controlBar,
                    controlBarDiameter: diameter, controlBarSymbolSize: symbol,
                    label: "Delete", action: { selection.confirmDelete = true }
                )
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .animation(.smooth(duration: 0.2), value: selection.notice)
    }

    private var countPill: some View {
        HStack(spacing: 8) {
            Text("\(selection.count) selected")
                .font(.karst(size: compactPhone ? 16 : 14, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(selection.allSelected ? "Select None" : "Select All") {
                if selection.allSelected { selection.clear() } else { selection.selectAll() }
            }
            .buttonStyle(.plain)
            .font(.karst(size: compactPhone ? 16 : 14))
            .foregroundStyle(theme.accentColor)
            .keyboardShortcut("a", modifiers: .command)
        }
        .padding(.horizontal, compactPhone ? 18 : 16)
        .frame(height: height)
        .frame(minWidth: 120, maxWidth: .infinity)
        .background { glass(Capsule()) }
    }

    private func glass<S: InsettableShape>(_ shape: S) -> some View {
        shape
            .fill(theme.surfaceRaised.opacity(StelloLayout.controlBarGlassFillOpacity))
            .overlay(shape.stroke(theme.border, lineWidth: 1))
            .glassEffect(.regular.interactive(), in: shape)
    }
}

// MARK: - Edit Tags

struct BulkTagEditor: View {
    let selection: GridSelection
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showAll = false
    @FocusState private var focused: Bool

    private static let categoryLabels: [String: String] = [
        "intent": "Why saved", "domain": "Domain", "subject": "Subject", "format": "Format",
        "tool": "Tool", "style": "Style", "mood": "Mood", "location": "Location", "color": "Color",
    ]

    var body: some View {
        let items = selection.items
        let onItems = BulkActions.tags(on: items)
        let suggestions = suggestions(items: items, onItems: onItems)
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = suggestions.contains { $0.name.lowercased() == query.lowercased() }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(items.count == 1 ? "Tags on 1 item" : "Tags on \(items.count) items")
                    .font(.karst(size: 13))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.karst(size: 14, weight: .medium))
                    .foregroundStyle(theme.accentColor)
            }
            TextField("Add a tag", text: $text)
                .textFieldStyle(.plain)
                .font(.karst(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.background))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? theme.accentColor : theme.border, lineWidth: 1))
                .focused($focused)
                .onSubmit {
                    if !query.isEmpty, !exact { add(query, category: "subject") }
                    else if let first = suggestions.first { add(first.name, category: first.category) }
                }
            if !query.isEmpty || !suggestions.isEmpty {
                VStack(spacing: 1) {
                    if !query.isEmpty, !exact {
                        option(title: "Add “\(query)”", detail: "New tag") { add(query, category: "subject") }
                    }
                    ForEach(suggestions) { s in
                        option(title: s.name, detail: Self.categoryLabels[s.category] ?? s.category) { add(s.name, category: s.category) }
                    }
                }
            }
            if !onItems.isEmpty {
                Text("On these items")
                    .font(.karst(size: 12))
                    .foregroundStyle(theme.textSecondary)
                TagFlowLayout(spacing: 6) {
                    ForEach(showAll ? onItems : Array(onItems.prefix(16))) { tag in
                        chip(tag, total: items.count)
                    }
                }
                if !showAll, onItems.count > 16 {
                    Button("Show all \(onItems.count)") { showAll = true }
                        .buttonStyle(.plain)
                        .font(.karst(size: 13))
                        .foregroundStyle(theme.accentColor)
                }
            } else {
                Text("No tags yet.")
                    .font(.karst(size: 13))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 420, alignment: .topLeading)
        .onAppear { focused = true }
    }

    private func suggestions(items: [Item], onItems: [SelectionTag]) -> [SelectionTag] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let onAll = Set(onItems.filter { $0.count == items.count }.map { $0.name.lowercased() })
        // Tags used anywhere in the grid, most used first.
        var counts: [String: (String, String, Int)] = [:]
        for item in selection.shownItems {
            for tag in item.tags where tag.category != "color" && tag.category != "collection" && !tag.name.isEmpty {
                let key = tag.name.lowercased()
                guard !onAll.contains(key), query.isEmpty || key.contains(query) else { continue }
                counts[key] = (tag.name, tag.category, (counts[key]?.2 ?? 0) + 1)
            }
        }
        return counts.values
            .sorted { a, b in
                let ap = a.0.lowercased().hasPrefix(query), bp = b.0.lowercased().hasPrefix(query)
                return ap != bp ? ap : a.2 > b.2
            }
            .prefix(6)
            .map { SelectionTag(name: $0.0, category: $0.1, count: $0.2) }
    }

    private func add(_ name: String, category: String) {
        let n = BulkActions.addTag(name, category: category, to: selection.items, context: context)
        text = ""
        selection.say(n == 1 ? "Added “\(name)” to 1 item" : "Added “\(name)” to \(n) items")
    }

    private func option(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(theme.textPrimary)
                Spacer()
                Text(detail).font(.karst(size: 12)).foregroundStyle(theme.textSecondary)
            }
            .font(.karst(size: 14))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.surfaceRaised.opacity(0.6)))
    }

    private func chip(_ tag: SelectionTag, total: Int) -> some View {
        HStack(spacing: 4) {
            Text(tag.name).foregroundStyle(theme.textPrimary)
            if tag.count < total {
                Text("\(tag.count)").foregroundStyle(theme.textSecondary).font(.karst(size: 11)).monospacedDigit()
            }
            Button {
                let n = BulkActions.removeTag(tag, from: selection.items, context: context)
                        selection.say(n == 1 ? "Removed “\(tag.name)” from 1 item" : "Removed “\(tag.name)” from \(n) items")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tag.name) from these items")
        }
        .font(.karst(size: 13))
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .overlay(Capsule().stroke(theme.border, lineWidth: 1))
        .help(Self.categoryLabels[tag.category] ?? tag.category)
    }
}

// MARK: - Selected look on a card

/// Accent ring inside the card and a filled check at the top left (web `.card.is-selected`).
struct GridSelectionMark: View {
    let isSelected: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.accentColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(theme.accentColor, lineWidth: 2)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.accentContrast)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(theme.accentColor))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(8)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isSelected)
        .allowsHitTesting(false)
    }
}
