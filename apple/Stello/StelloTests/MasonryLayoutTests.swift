import Testing
import SwiftUI
@testable import Stello

@Suite("MasonryLayout")
struct MasonryLayoutTests {

    let layout = MasonryLayout()

    // MARK: Column count

    @Test("480pt → 2 columns")
    func width480() { #expect(layout.columnCount(for: 480) == 2) }

    @Test("700pt → 3 columns")
    func width700() { #expect(layout.columnCount(for: 700) == 3) }

    @Test("1000pt → 4 columns")
    func width1000() { #expect(layout.columnCount(for: 1000) == 4) }

    @Test("1400pt → 5 columns")
    func width1400() { #expect(layout.columnCount(for: 1400) == 5) }

    @Test("Boundaries: exactly 500 → 2, 501 → 3")
    func boundaries() {
        #expect(layout.columnCount(for: 500) == 2)
        #expect(layout.columnCount(for: 501) == 3)
        #expect(layout.columnCount(for: 768) == 3)
        #expect(layout.columnCount(for: 769) == 4)
        #expect(layout.columnCount(for: 1200) == 4)
        #expect(layout.columnCount(for: 1201) == 5)
    }

    // MARK: Shortest-column packing

    @Test("All columns filled when cards > columns", arguments: 2...5)
    func allColumnsFilled(colCount: Int) {
        let cardCount = colCount + 3
        let assignments = MasonryLayout.distribute(count: cardCount, colCount: colCount)
        let uniqueCols = Set(assignments)
        #expect(uniqueCols.count == colCount,
                "Expected \(colCount) filled columns, got \(uniqueCols.count)")
    }

    @Test("No column is empty when cards == columns")
    func exactFit() {
        for cols in 2...5 {
            let assignments = MasonryLayout.distribute(count: cols, colCount: cols)
            #expect(Set(assignments).count == cols)
        }
    }

    @Test("Cards distributed across all columns for 20 items at each breakpoint")
    func distributionAt20Cards() {
        for (width, expectedCols) in [(480.0, 2), (700.0, 3), (1000.0, 4), (1400.0, 5)] {
            let cols = layout.columnCount(for: CGFloat(width))
            #expect(cols == expectedCols)
            let assignments = MasonryLayout.distribute(count: 20, colCount: cols)
            #expect(Set(assignments).count == cols)
        }
    }
}
