import SwiftUI
import SwiftData

struct ItemCardView: View {
    let item: Item

    private var coverColor: Color {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .pink,
            .teal, .indigo, .cyan, .mint, .yellow
        ]
        return palette[abs(item.slug.hashValue) % palette.count]
    }

    private var symbolName: String {
        switch item.domain {
        case "figma.com":            "pencil.and.ruler"
        case "dribbble.com":         "paintbrush"
        case "instagram.com":        "camera"
        case "twitter.com", "x.com": "text.bubble"
        case "github.com":           "chevron.left.forwardslash.chevron.right"
        case "youtube.com":          "play.rectangle"
        case "spotify.com":          "music.note"
        case "medium.com":           "newspaper"
        case "arxiv.org":            "doc.text.magnifyingglass"
        default:                     "doc.text"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverArea
            infoArea
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
    }

    private var coverArea: some View {
        coverColor
            .opacity(0.12)
            .frame(height: 130)
            .overlay(alignment: .center) {
                Image(systemName: symbolName)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(coverColor)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 12,
                    style: .continuous
                )
            )
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let domain = item.domain, !domain.isEmpty {
                Text(domain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(10)
    }
}

#Preview {
    ItemCardView(item: SeedData.sampleItem)
        .frame(width: 200)
        .padding()
}
