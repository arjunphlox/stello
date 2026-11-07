import CoreGraphics

/// Every card's frame, worked out from data alone, so the grid can build only the cards
/// near the viewport. Same packing as `MasonryLayout`: each card goes in the shortest
/// column. Heights are exact: a cover is `width / aspect`, and every other card is 140pt.
nonisolated struct VirtualMasonryModel: Equatable {
    static let fallbackCardHeight: CGFloat = 140

    private(set) var frames: [CGRect] = []
    private(set) var contentHeight: CGFloat = 0
    /// Grid-space top of each week's first card and bottom of its last card.
    private(set) var weekTops: [String: CGFloat] = [:]
    private(set) var weekBottoms: [String: CGFloat] = [:]
    /// Card indices per column. A column's frames only ever move down the page.
    private var columns: [[Int]] = []

    init() {}

    /// `aspects[i]` is card i's width over height, or 0 when it shows no cover.
    init(aspects: [Double], weekKeys: [String], width: CGFloat, columnCount: Int, spacing: CGFloat) {
        guard width > 0, columnCount > 0 else { return }
        let columnWidth = (width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        var tops = [CGFloat](repeating: 0, count: columnCount)
        columns = [[Int]](repeating: [], count: columnCount)
        frames.reserveCapacity(aspects.count)

        for (index, aspect) in aspects.enumerated() {
            var column = 0
            for candidate in 1..<max(columnCount, 1) where tops[candidate] < tops[column] {
                column = candidate
            }
            let height = aspect > 0 ? columnWidth / CGFloat(aspect) : Self.fallbackCardHeight
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + spacing), y: tops[column],
                width: columnWidth, height: height
            )
            frames.append(frame)
            columns[column].append(index)
            tops[column] += height + spacing

            if index < weekKeys.count {
                let key = weekKeys[index]
                if weekTops[key] == nil { weekTops[key] = frame.minY }
                weekBottoms[key] = frame.maxY
            }
        }
        contentHeight = max((tops.max() ?? 0) - spacing, 0)
    }

    /// Indices of the cards touching `minY...maxY`, in display order.
    func visibleIndices(minY: CGFloat, maxY: CGFloat) -> [Int] {
        var result: [Int] = []
        for column in columns {
            var low = 0
            var high = column.count
            while low < high {
                let middle = (low + high) / 2
                if frames[column[middle]].maxY < minY { low = middle + 1 } else { high = middle }
            }
            var position = low
            while position < column.count, frames[column[position]].minY <= maxY {
                result.append(column[position])
                position += 1
            }
        }
        return result.sorted()
    }
}
