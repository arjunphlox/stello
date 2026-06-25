import SwiftUI
import SwiftData
import ImageIO
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Image-forward masonry card mirroring the Stello web app: OG images render cleanly (title
/// below or omitted); generated/gradient covers keep the title overlay. Text cards show
/// title + summary. Domain pill tinted by dominant color tag.
struct ItemCardView: View {
    let item: Item
    var isSelected: Bool = false
    @Environment(\.appTheme) private var theme

    private static let hues: [Double] = [18, 80, 38, 140, 25, 45, 12, 100]
    private static let textWordCap = 40

    private func stableHash(_ s: String) -> Int {
        s.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
    }

    private var coverHue: Double {
        Self.hues[abs(stableHash(item.slug)) % Self.hues.count] / 360.0
    }

    private var primaryImage: ItemImage? { item.coverImage }

    private var hasImage: Bool { item.hasRenderableCover }

    /// Generated gradient covers from seed backfill — keep title overlay on cover.
    private var isGeneratedCover: Bool {
        guard hasImage else { return false }
        return primaryImage?.source == "generated"
    }

    private var aspect: CGFloat {
        if let img = primaryImage, let w = img.width, let h = img.height, w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        return 1200.0 / 630.0
    }

    private var hasText: Bool {
        guard !hasImage else { return false }
        guard let s = item.summary else { return false }
        return s.count > 30 && !s.hasPrefix("Saved from")
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? theme.accentColor : .clear, lineWidth: 2.5)
            }
            .shadow(color: .black.opacity(theme.mode == .dark ? 0.30 : 0.08), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder private var cardContent: some View {
        if hasImage, let data = primaryImage?.data, let img = Self.platformImage(data) {
            if isGeneratedCover {
                imageWithOverlay(img)
            } else {
                fetchedImageCard(img)
            }
        } else if hasText {
            textCard
        } else {
            placeholderCard
        }
    }

    private func fetchedImageCard(_ img: Image) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            img
                .resizable()
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)

            HStack(alignment: .bottom, spacing: 6) {
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                domainPill
            }
            .padding(10)
            .background(theme.backgroundSubtle)
        }
    }

    private func imageWithOverlay(_ img: Image) -> some View {
        img
            .resizable()
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { overlayFooter(includeTitle: true) }
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.title.isEmpty {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
            }
            Text(Self.truncatedWords(item.summary ?? "", limit: Self.textWordCap))
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary.opacity(0.92))
                .lineLimit(8)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(14)
        .padding(.bottom, item.domain?.isEmpty == false ? 26 : 0)
        .background(
            Color(hue: coverHue,
                  saturation: theme.mode == .dark ? 0.15 : 0.12,
                  brightness: theme.mode == .dark ? 0.14 : 0.92)
        )
        .overlay(alignment: .bottomTrailing) {
            if item.domain?.isEmpty == false {
                domainPill.padding(10)
            }
        }
    }

    private var placeholderCard: some View {
        ZStack {
            placeholderGradient
            Text(String(item.title.first ?? "?").uppercased())
                .font(.system(size: 46, weight: .light, design: .serif))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 140)
        .overlay(alignment: .bottom) { overlayFooter(includeTitle: true) }
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

    @ViewBuilder
    private func overlayFooter(includeTitle: Bool) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.45), .black.opacity(0.82)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 6) {
                if includeTitle, !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
                Spacer(minLength: 4)
                domainPill
            }
            .padding(10)
        }
    }

    @ViewBuilder private var domainPill: some View {
        if let domain = item.domain, !domain.isEmpty {
            let tint = dominantColor ?? .white
            Text(domain)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.22))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5))
        }
    }

    // MARK: - Helpers

    static func truncatedWords(_ text: String, limit: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > limit else { return text }
        return words.prefix(limit).joined(separator: " ") + "…"
    }

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

#Preview {
    ItemCardView(item: SeedData.sampleItem)
        .frame(width: 220)
        .padding()
        .background(Color(hex: "#111110"))
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}
