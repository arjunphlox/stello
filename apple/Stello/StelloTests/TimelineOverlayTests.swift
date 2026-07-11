import Testing
@testable import Stello

@Suite("TimelineOverlay.weekKey band mapping")
struct TimelineOverlayTests {

    // Three bars of unequal height with 4pt gaps between them, mirroring
    // `timelineBarLayouts(scrollTopInset:)`'s output shape:
    //   "w1": [0, 20]      (height 20)
    //   "w2": [24, 30]     (height 6, short — the case that broke nearest-center)
    //   "w3": [34, 80]     (height 46)
    let entries: [(key: String, layout: WeekBarLayout)] = [
        ("w1", WeekBarLayout(topY: 0, bottomY: 20)),
        ("w2", WeekBarLayout(topY: 24, bottomY: 30)),
        ("w3", WeekBarLayout(topY: 34, bottomY: 80)),
    ]

    @Test("Pointer inside a bar's own rect resolves to that bar")
    func withinBar() {
        #expect(TimelineOverlay.weekKey(at: 10, entries: entries) == "w1")
        #expect(TimelineOverlay.weekKey(at: 27, entries: entries) == "w2")
        #expect(TimelineOverlay.weekKey(at: 60, entries: entries) == "w3")
    }

    @Test("Pointer just below a short bar (still above the old midpoint) resolves to that bar, not the one above")
    func regressionShortBarGap() {
        // Old nearest-center bug: w2's midY is 27, w1's midY is 10. A pointer at
        // y=22 (in the gap just below w1, just above w2) is closer to w2 (|22-27|=5)
        // than w1 (|22-10|=12) by distance — but under band mapping the boundary
        // between w1 and w2 is the gap midpoint (20+24)/2 = 22, so y=22 must select w2.
        #expect(TimelineOverlay.weekKey(at: 21, entries: entries) == "w1")
        #expect(TimelineOverlay.weekKey(at: 22, entries: entries) == "w2")
        #expect(TimelineOverlay.weekKey(at: 23, entries: entries) == "w2")
    }

    @Test("Gap boundary between w2 and w3 sits at the gap midpoint (30+34)/2 = 32")
    func gapBoundaryBetweenSecondAndThird() {
        #expect(TimelineOverlay.weekKey(at: 31, entries: entries) == "w2")
        #expect(TimelineOverlay.weekKey(at: 32, entries: entries) == "w3")
    }

    @Test("Pointer above the first bar clamps to the first bar")
    func clampsAboveFirst() {
        #expect(TimelineOverlay.weekKey(at: -50, entries: entries) == "w1")
    }

    @Test("Pointer below the last bar clamps to the last bar")
    func clampsBelowLast() {
        #expect(TimelineOverlay.weekKey(at: 5000, entries: entries) == "w3")
    }

    @Test("Empty entries resolve to nil")
    func emptyEntries() {
        #expect(TimelineOverlay.weekKey(at: 10, entries: []) == nil)
    }

    @Test("Order of input entries doesn't matter — sorted internally by topY")
    func orderIndependence() {
        let shuffled = Array(entries.reversed())
        #expect(TimelineOverlay.weekKey(at: 10, entries: shuffled) == "w1")
        #expect(TimelineOverlay.weekKey(at: 60, entries: shuffled) == "w3")
    }
}
