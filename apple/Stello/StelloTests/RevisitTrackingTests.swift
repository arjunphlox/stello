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
}
