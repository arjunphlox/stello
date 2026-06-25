import SwiftUI
import SwiftData
import ImageIO
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Image-forward masonry card mirroring the Stello web app: the cover image fills the
/// card at its natural aspect ratio, with the title over a bottom scrim and a domain
/// pill (tinted by the dominant color tag) in the bottom-right. Text and letter-placeholder
/// variants cover items without an image.
struct ItemCardView: View {
    let item: Item
    var isSelected: Bool = false
    @Environment(\.appTheme) private var theme

    // Placeholder hue palette (from BUILD_SPEC) for text / letter cards.
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

    private var aspect: CGFloat {
        if let img = primaryImage, let w = img.width, let h = img.height, w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        return 1200.0 / 630.0 // OG default
    }

    /// Mirrors web `hasTextContent`: text card only when image-less, summary is substantive,
    /// and not the generic capture stub.
    private var hasText: Bool {
        guard !hasImage else { return false }
        guard let s = item.summary else { return false }
        return s.count > 30 && !s.hasPrefix("Saved from")
    }

    /// Highest-weight `color` tag mapped to a Color, else nil (pill falls back to white, like web).
    private var dominantColor: Color? {
        let colorTags = (item.tags ?? [])
            .filter { $0.category == "color" }
            .sorted { $0.weight > $1.weight }
        for t in colorTags { if let c = Self.namedColor(t.name) { return c } }
        return nil
    }

    var body: some View {
        visual
            .overlay(alignment: .bottom) { bottomOverlay }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? theme.accentColor : .clear, lineWidth: 2.5)
            }
            .shadow(color: .black.opacity(theme.mode == .dark ? 0.30 : 0.08), radius: 5, x: 0, y: 2)
    }

    // MARK: - Visual variants

    @ViewBuilder private var visual: some View {
        if hasImage, let data = primaryImage?.data, let img = Self.platformImage(data) {
            img
                .resizable()
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
        } else if hasText {
            textCard
        } else {
            placeholderCard
        }
    }

    /// Web `.card-text-content`: summary only in the tinted box — no title, no multi-line dump.
    private var textCard: some View {
        Text(Self.truncatedWords(item.summary ?? "", limit: Self.textWordCap))
            .font(.system(size: 13))
            .foregroundStyle(theme.textPrimary)
            .lineLimit(8)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(14)
            .padding(.bottom, item.domain?.isEmpty == false ? 26 : 0)
            .background(
                Color(hue: coverHue,
                      saturation: theme.mode == .dark ? 0.15 : 0.12,
                      brightness: theme.mode == .dark ? 0.14 : 0.92)
            )
    }

    private var placeholderCard: some View {
        ZStack {
            Color(hue: coverHue,
                  saturation: theme.mode == .dark ? 0.20 : 0.10,
                  brightness: theme.mode == .dark ? 0.16 : 0.93)
            Text(String(item.title.first ?? "?").uppercased())
                .font(.system(size: 46, weight: .light, design: .serif))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 140)
    }

    // MARK: - Overlays

    @ViewBuilder private var bottomOverlay: some View {
        if hasImage {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.62)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: 88)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: 6) {
                    Text(item.title.isEmpty ? "" : item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                    Spacer(minLength: 4)
                    domainPill
                }
                .padding(10)
            }
        } else {
            HStack {
                Spacer()
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

    /// Maps common color-tag words to a representative Color (for the domain pill tint).
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
