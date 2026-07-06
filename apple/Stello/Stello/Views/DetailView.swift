import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var item: Item
    var embedsInPanel: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            CardSubcards(item: item, embedsInPanel: embedsInPanel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(embedsInPanel ? Color.clear : theme.background)
        .onAppear { StelloStore.recordOpen(for: item) }
    }
}

// MARK: - Flow layout for tag chips

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DetailView(item: SeedData.enrichedSampleItem)
    }
    .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
    .preferredColorScheme(.dark)
}
