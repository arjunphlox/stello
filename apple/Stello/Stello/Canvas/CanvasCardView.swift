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

/// A card on the canvas: the cover only, at the web's 274-wide world size, with the
/// source pill. Details come later from the ≡ button (stage 3).
struct CanvasCardView: View {
    let item: Item
    let height: CGFloat
    var isSelected = false
    /// 1 / zoom, so the pill and outline keep one size on screen at any zoom (web).
    var counterScale: CGFloat = 1

    @Environment(\.appTheme) private var theme
    @State private var decodedKey: String?

    private var image: ItemImage? { item.coverImage }
    private var cacheKey: String { "\(item.id.uuidString)-\(image?.data?.count ?? 0)" }

    var body: some View {
        let _ = decodedKey
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
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .bottomTrailing) { pill }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
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

    /// The source pill keeps 11pt on screen at any zoom (world size = 11 / zoom) and
    /// truncates inside the card. It hides once the card is too small on screen to
    /// hold it, so pills never outgrow their cards or run into each other.
    @ViewBuilder private var pill: some View {
        let label = item.displayLink
        let onScreen = CanvasMetrics.cardWidth / counterScale
        if !label.isEmpty, onScreen >= 110 {
            let s = counterScale
            Text(label)
                .font(.karst(size: 11 * s, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7 * s)
                .padding(.vertical, 3 * s)
                .background(.black.opacity(0.45))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(8 * s)
                .frame(maxWidth: CanvasMetrics.cardWidth, alignment: .trailing)
        }
    }
}
