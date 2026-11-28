import Testing
import Foundation
import CoreGraphics
@testable import Stello

/// Grid selection + bulk actions (web `GridSelect`): selection rules, the tag list across a
/// selection, and the Copy to Figma moodboard.
@MainActor
@Suite("GridSelection")
struct GridSelectionTests {

    private func items(_ n: Int) -> [Item] {
        (0..<n).map { Item(slug: "item-\($0)", title: "Item \($0)", sourceURL: "https://example.com/\($0)") }
    }

    @Test("toggle adds and removes; clear empties")
    func toggleAndClear() {
        let sel = GridSelection()
        let list = items(3)
        sel.gridChanged(list)
        sel.toggle(list[0])
        sel.toggle(list[2])
        #expect(sel.count == 2 && sel.contains(list[0]) && sel.contains(list[2]))
        sel.toggle(list[0])
        #expect(sel.count == 1 && !sel.contains(list[0]))
        sel.clear()
        #expect(!sel.isActive)
    }

    @Test("⇧-click selects the run between the last card and this one, in grid order")
    func extendRange() {
        let sel = GridSelection()
        let list = items(6)
        sel.gridChanged(list)
        sel.toggle(list[1])
        sel.extend(to: list[4])
        #expect(sel.items.map(\.slug) == ["item-1", "item-2", "item-3", "item-4"])
    }

    @Test("items the grid stops showing leave the selection")
    func pruneOnFilter() {
        let sel = GridSelection()
        let list = items(4)
        sel.gridChanged(list)
        sel.toggle(list[0])
        sel.toggle(list[3])
        sel.gridChanged(Array(list.prefix(2)))
        #expect(sel.count == 1 && sel.contains(list[0]))
    }

    @Test("Select All keeps everything selected as more of the library loads")
    func selectAllFollowsLoading() {
        let sel = GridSelection()
        let list = items(5)
        sel.gridChanged(Array(list.prefix(2)))
        sel.selectAll()
        #expect(sel.count == 2)
        sel.gridChanged(list)
        #expect(sel.count == 5 && sel.allSelected)
        sel.toggle(list[4])
        sel.gridChanged(list)
        #expect(sel.count == 4)
    }

    @Test("tags across a selection count each item once, most shared first")
    func tagUnion() {
        let list = items(3)
        list[0].tags = [ItemTag(name: "brand", category: "subject"), ItemTag(name: "warm", category: "mood")]
        list[1].tags = [ItemTag(name: "brand", category: "subject")]
        list[2].tags = [ItemTag(name: "brand", category: "subject"), ItemTag(name: "x", category: "collection")]
        let tags = BulkActions.tags(on: list)
        #expect(tags.map(\.name) == ["brand", "warm"])
        #expect(tags.first?.count == 3)
    }

    @Test("only web links count as links")
    func linksOnlyHTTP() {
        let list = items(2) + [Item(slug: "note", title: "Note"), Item(slug: "file", title: "F", sourceURL: "file:///tmp/a")]
        #expect(BulkActions.links(list).count == 2)
    }
}

@Suite("FigmaMoodboard")
struct FigmaMoodboardTests {

    @Test("up to four columns, each card in the shortest one")
    func layoutColumns() {
        let one = FigmaMoodboard.layout(aspects: [1])
        #expect(one.width == FigmaMoodboard.cardWidth)
        let nine = FigmaMoodboard.layout(aspects: Array(repeating: 2, count: 9))
        #expect(nine.width == 3 * FigmaMoodboard.cardWidth + 2 * FigmaMoodboard.gap)
        let many = FigmaMoodboard.layout(aspects: Array(repeating: 1, count: 40))
        #expect(Set(many.placed.map(\.x)).count == 4)
        // A tall first card pushes the next ones into the other columns.
        let mixed = FigmaMoodboard.layout(aspects: [0.5, 2, 2, 2])
        #expect(mixed.placed[1].x != mixed.placed[0].x)
        #expect(mixed.placed[3].y > 0)
    }

    @Test("titles are escaped and name the layer; imageless items get a text card")
    func svgText() {
        let svg = FigmaMoodboard.svg(for: [.init(title: "A & B <C>", domain: "example.com", image: nil)])
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.contains("<g id=\"A &amp; B &lt;C&gt;\">"))
        #expect(svg.contains("example.com"))
        #expect(!svg.contains("<image"))
    }

    @Test("long titles wrap at word boundaries")
    func wrap() {
        let lines = FigmaMoodboard.wrap("one two three four five six seven eight", max: 10)
        #expect(lines.allSatisfy { $0.count <= 10 })
        #expect(lines.joined(separator: " ") == "one two three four five six seven eight")
    }
}
