import Testing
import Foundation
import SwiftData
@testable import Stello

@Suite("Revisit tracking")
struct RevisitTrackingTests {

    @Test("Opening sets lastOpenedAt and increments openCount")
    func openingSetsFields() throws {
        StelloStore.resetRevisitSession()
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Revisit me")
        context.insert(item)

        let updatedAtBefore = item.updatedAt
        StelloStore.recordOpen(for: item)

        #expect(item.openCount == 1)
        #expect(item.lastOpenedAt != nil)
        #expect(item.updatedAt == updatedAtBefore)
    }

    @Test("Second open in same session does not double-count")
    func sameSessionDebounced() throws {
        StelloStore.resetRevisitSession()
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Revisit me")
        context.insert(item)

        StelloStore.recordOpen(for: item)
        let firstOpenedAt = item.lastOpenedAt
        StelloStore.recordOpen(for: item)

        #expect(item.openCount == 1)
        #expect(item.lastOpenedAt == firstOpenedAt)
    }

    @Test("Fresh session increments openCount again")
    func newSessionIncrementsAgain() throws {
        StelloStore.resetRevisitSession()
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let item = Item(title: "Revisit me")
        context.insert(item)

        StelloStore.recordOpen(for: item)
        StelloStore.resetRevisitSession()
        StelloStore.recordOpen(for: item)

        #expect(item.openCount == 2)
        #expect(item.lastOpenedAt != nil)
    }

    @Test("Consecutive different-item opens each record, same-item re-open stays debounced")
    func consecutiveDifferentItemsEachRecord() throws {
        StelloStore.resetRevisitSession()
        let container = try StelloStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let itemA = Item(title: "Item A")
        let itemB = Item(title: "Item B")
        let itemC = Item(title: "Item C")
        context.insert(itemA)
        context.insert(itemB)
        context.insert(itemC)

        // Simulates browsing through a panel/list: DetailView mounts for each
        // item identity change (e.g. panel selection change, related-item nav).
        StelloStore.recordOpen(for: itemA)
        StelloStore.recordOpen(for: itemB)
        StelloStore.recordOpen(for: itemC)

        #expect(itemA.openCount == 1)
        #expect(itemB.openCount == 1)
        #expect(itemC.openCount == 1)

        // Re-opening an already-opened item in the same session stays debounced.
        let itemALastOpened = itemA.lastOpenedAt
        StelloStore.recordOpen(for: itemA)

        #expect(itemA.openCount == 1)
        #expect(itemA.lastOpenedAt == itemALastOpened)
    }
}
