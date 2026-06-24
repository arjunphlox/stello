import SwiftUI
import SwiftData

struct ItemCardView: View {
    let item: Item
    @Environment(\.appTheme) private var theme

    // Hues from BUILD_SPEC placeholder palette
    private static let hues: [Double] = [18, 80, 38, 140, 25, 45, 12, 100]

    private var coverHue: Double {
        let idx = abs(item.slug.hashValue) % Self.hues.count
        return Self.hues[idx] / 360.0
    }

    private var coverBG: Color {
        Color(hue: coverHue, saturation: 0.4, brightness: theme.mode == .dark ? 0.26 : 0.88)
    }

    private var coverFG: Color {
        Color(hue: coverHue, saturation: 0.55, brightness: theme.mode == .dark ? 0.75 : 0.50)
    }

    private var symbolName: String {
        switch item.domain {
        case "figma.com":              "pencil.and.ruler"
        case "dribbble.com":           "paintbrush"
        case "instagram.com":          "camera"
        case "twitter.com", "x.com":   "text.bubble"
        case "github.com":             "chevron.left.forwardslash.chevron.right"
        case "youtube.com":            "play.rectangle"
        case "spotify.com":            "music.note"
        case "medium.com":             "newspaper"
        case "arxiv.org":              "doc.text.magnifyingglass"
        default:                       "doc.text"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverArea
            infoArea
        }
        .background(theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(theme.mode == .dark ? 0.28 : 0.07), radius: 4, x: 0, y: 2)
    }

    private var coverArea: some View {
        ZStack {
            coverBG
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(coverFG)
        }
        .frame(height: 120)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 10,
                style: .continuous
            )
        )
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let domain = item.domain, !domain.isEmpty {
                Text(domain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(theme.borderSubtle)
                    .clipShape(Capsule())
            }
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(3)
        }
        .padding(10)
    }
}

#Preview {
    ItemCardView(item: SeedData.sampleItem)
        .frame(width: 200)
        .padding()
        .background(Color(hex: "#111110"))
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}
