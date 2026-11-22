import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// A library item carried from the grid to the canvas. Its own type, so the
    /// window's file / text drop import never treats it as a new save.
    static let stelloItem = UTType(exportedAs: "com.arjunphlox.stello.item")
}

/// Payload for dragging a grid card onto the canvas.
struct CanvasDragItem: Codable, Transferable {
    let slug: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .stelloItem)
    }
}

/// A card on the canvas: the cover, at the web's 274-wide world size, with the
/// source pill. A tap on the card or its ≡ button opens it in place: the details
/// grow out of the same card, over what is below, without moving anything.
struct CanvasCardView: View {
    let item: Item
    let height: CGFloat
    var isSelected = false
    /// 1 / zoom, so the pill and outline keep one size on screen at any zoom (web).
    var counterScale: CGFloat = 1
    var detailsOpen = false
    var onDetails: (() -> Void)? = nil
    /// Use / Rejected (Layer 2) and its reason.
    var mark: CanvasMark? = nil
    var reason: String? = nil

    @Environment(\.appTheme) private var theme
    @State private var decodedKey: String?

    /// Web `.lc-dom`: rgba(20, 20, 18, 0.78).
    private static let pillFill = Color(red: 20 / 255, green: 20 / 255, blue: 18 / 255).opacity(0.78)

    private var image: ItemImage? { item.coverImage }
    private var cacheKey: String { "\(item.id.uuidString)-\(image?.data?.count ?? 0)" }

    var body: some View {
        let _ = decodedKey
        // Open: the details grow out of the cover inside one card (web
        // `.lc-card.has-det`), over what is below, without moving other cards.
        VStack(alignment: .leading, spacing: 0) {
            cover
            if detailsOpen {
                CanvasDetailsCard(item: item)
            }
        }
        .frame(width: CanvasMetrics.cardWidth, alignment: .topLeading)
        .background {
            if detailsOpen {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceRaised)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if let mark {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(mark.color, lineWidth: 3 * counterScale)
            } else if detailsOpen {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.border, lineWidth: 1 * counterScale)
            }
        }
        .shadow(color: .black.opacity(detailsOpen ? 0.28 : 0), radius: 16, y: 6)
        .overlay(alignment: .topLeading) { markBadge }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.accentColor, lineWidth: 1.5 * counterScale)
                    .padding(-4 * counterScale)
            }
        }
        .contentShape(Rectangle())
        .task(id: cacheKey) {
            guard let data = image?.data, !data.isEmpty else { return }
            if await CoverImageCache.decode(data, key: cacheKey) != nil { decodedKey = cacheKey }
        }
    }

    /// The cover with its source pill and ≡ button.
    private var cover: some View {
        ZStack {
            if let data = image?.data, !data.isEmpty,
               let cg = CoverImageCache.decodedImage(forKey: cacheKey) {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                (theme.mode == .light ? theme.borderSubtle : theme.surfaceRaised)
                Image(systemName: ItemCardView.kindGlyph(item.kind))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(theme.textDim)
            }
        }
        .frame(width: CanvasMetrics.cardWidth, height: height)
        .grayscale(mark == .rejected ? 0.6 : 0)
        .clipped()
        .overlay(alignment: .bottomTrailing) { pillRow }
    }

    /// "USE · reason" above the card (web `mark-badge`), screen sized like the pill.
    @ViewBuilder private var markBadge: some View {
        if let mark, CanvasMetrics.cardWidth / counterScale >= 110 {
            let s = counterScale
            let r = (reason ?? "").trimmingCharacters(in: .whitespaces)
            Text(r.isEmpty ? mark.label.uppercased() : "\(mark.label.uppercased()) · \(r)")
                .font(.karst(size: 10 * s, weight: .medium))
                .tracking(0.5 * s)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 7 * s)
                .padding(.vertical, 3 * s)
                .foregroundStyle(.white)
                .background(mark.color, in: RoundedRectangle(cornerRadius: 7 * s, style: .continuous))
                .frame(maxWidth: CanvasMetrics.cardWidth, alignment: .leading)
                .offset(y: -26 * s)
        }
    }

    /// The source pill and ≡ keep 11pt on screen at any zoom (world size = 11 / zoom)
    /// and truncate inside the card. They hide once the card is too small on screen
    /// to hold them, so pills never outgrow their cards or run into each other.
    @ViewBuilder private var pillRow: some View {
        let label = item.displayLink
        let onScreen = CanvasMetrics.cardWidth / counterScale
        if onScreen >= 110 {
            let s = counterScale
            HStack(spacing: 4 * s) {
                if !label.isEmpty {
                    Text(label)
                        .font(.karst(size: 12 * s, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 9 * s)
                        .frame(height: 22 * s)
                        .background(Self.pillFill)
                        .foregroundStyle(Color(white: 0.933))
                        .clipShape(Capsule())
                }
                if let onDetails {
                    Button(action: onDetails) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10 * s, weight: .medium))
                            .frame(width: 22 * s, height: 22 * s)
                            .background(detailsOpen ? theme.accentColor : Self.pillFill, in: Circle())
                            .foregroundStyle(detailsOpen ? theme.accentContrast : Color(white: 0.933))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(detailsOpen ? "Hide details" : "Details")
                    .accessibilityLabel("Details")
                }
            }
            .padding(8 * s)
            .frame(maxWidth: CanvasMetrics.cardWidth, alignment: .trailing)
        }
    }
}

/// The details inside an open card (web `details`): title, source · kind · saved
/// date, colour swatches, style, tags, collection, place, why saved, and a summary
/// quote. World sized, so it scales with its card. No bold text.
struct CanvasDetailsCard: View {
    let item: Item
    @Environment(\.appTheme) private var theme

    private func top(_ cat: String, _ min: Double = 0) -> [ItemTag] {
        item.tags.filter { $0.category == cat && $0.weight >= min }.sorted { $0.weight > $1.weight }
    }

    private var rows: [(String, String)] {
        var out: [(String, String)] = []
        let style = top("style", 0.4).prefix(4).map(\.name).joined(separator: ", ")
        let tags = top("subject", 0.5).filter { !CanvasSimilarity.skipSubject.contains($0.name) }
            .prefix(5).map(\.name).joined(separator: ", ")
        let coll = top("collection").prefix(2).map(\.name).joined(separator: ", ")
        let place = top("location", 0.3).first.map { CanvasSimilarity.cap($0.name) } ?? ""
        let why = top("intent").prefix(3).map { CanvasSimilarity.cap($0.name).lowercased() }.joined(separator: ", ")
        if !style.isEmpty { out.append(("Style", style)) }
        if !tags.isEmpty { out.append(("Tags", tags)) }
        if !coll.isEmpty { out.append(("Collection", coll)) }
        if !place.isEmpty { out.append(("Place", place)) }
        if !why.isEmpty { out.append(("Why saved", why)) }
        return out
    }

    private var meta: String {
        let kind = CanvasSimilarity.kindName(kindLine: item.cardKindLine, kind: item.kind,
                                             hasURL: !(item.sourceURL ?? "").isEmpty)
        let saved = "Saved " + item.addedAt.formatted(.dateTime.month(.abbreviated).day().year())
        return [item.domain ?? item.displayLink, kind, saved].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title.isEmpty ? (item.domain ?? "Untitled") : item.title)
                .font(.karst(size: 15))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            Text(meta)
                .font(.karst(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
            let swatches = top("color", 0.15).prefix(3).compactMap { ItemCardView.namedColor($0.name) }
            if !swatches.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(theme.border, lineWidth: 0.5))
                    }
                }
            }
            ForEach(rows, id: \.0) { label, value in
                (Text(label + "  ").foregroundStyle(theme.textDim) + Text(value).foregroundStyle(theme.textPrimary))
                    .font(.karst(size: 11))
                    .lineLimit(2)
            }
            if let note = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text("“\(note)”")
                    .font(.karst(size: 11, italic: true))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: CanvasMetrics.cardWidth, alignment: .leading)
    }
}
