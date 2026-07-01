import SwiftUI

struct MasonryLayout: Layout {
    var spacing: CGFloat = 12
    /// When set, overrides width-based column count (clamped to 1…12).
    var forcedColumns: Int? = nil

    // Internal so tests can verify column-count decisions directly.
    func columnCount(for width: CGFloat) -> Int {
        if width <= 500 { return 2 }
        if width <= 768 { return 3 }
        if width <= 1200 { return 4 }
        return 5
    }

    func resolvedColumnCount(for width: CGFloat) -> Int {
        if let forcedColumns {
            return min(max(forcedColumns, 1), 12)
        }
        return columnCount(for: width)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? 375
        let cols = resolvedColumnCount(for: width)
        let colWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)

        var heights = [CGFloat](repeating: 0, count: cols)
        for subview in subviews {
            let idx = heights.indices.min(by: { heights[$0] < heights[$1] })!
            let h = subview.sizeThatFits(ProposedViewSize(width: colWidth, height: nil)).height
            heights[idx] += h + spacing
        }
        let total = (heights.max() ?? 0) - spacing
        return CGSize(width: width, height: max(0, total))
    }

    // Assigns each card to a column using shortest-column packing.
    // Heights are uniform (value 1.0) for testing column distribution.
    static func distribute(count: Int, colCount: Int) -> [Int] {
        var heights = [Double](repeating: 0, count: colCount)
        return (0..<count).map { _ in
            let col = heights.indices.min(by: { heights[$0] < heights[$1] })!
            heights[col] += 1.0
            return col
        }
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }
        let cols = resolvedColumnCount(for: bounds.width)
        let colWidth = (bounds.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)

        var tops = [CGFloat](repeating: bounds.minY, count: cols)
        for subview in subviews {
            let col = tops.indices.min(by: { tops[$0] < tops[$1] })!
            let x = bounds.minX + CGFloat(col) * (colWidth + spacing)
            let size = subview.sizeThatFits(ProposedViewSize(width: colWidth, height: nil))
            subview.place(
                at: CGPoint(x: x, y: tops[col]),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: colWidth, height: size.height)
            )
            tops[col] += size.height + spacing
        }
    }
}
