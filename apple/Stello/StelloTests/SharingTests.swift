import Testing
import Foundation
import SwiftData
@testable import Stello

/// Audience sharing on the Apple side. The rules must match src/lib/sharing.js
/// (see test/sharing.test.js for the web's copy of the same cases).
@Suite("Audience sharing")
@MainActor
struct SharingTests {
    private func audience(_ s: SharingSettings, _ id: String) -> SharingSettings.Audience? {
        s.audiences.first { $0.id == id }
    }

    @Test func defaultsMatchTheWeb() {
        let ids = SharingSettings.defaults.audiences.map(\.id)
        #expect(ids == ["family", "close-friends", "acquaintances", "public"])
        #expect(SharingSettings.defaults.audiences.allSatisfy { $0.clock == .init() })
    }

    @Test func circlesNestListsDont() {
        var s = SharingSettings.defaults
        s.audiences.append(.init(id: "trip", name: "Trip", kind: "list", rank: nil, location: "city", color: nil, deleted_at: nil, clock: .init()))
        #expect(s.isVisible(["close-friends"], to: "family"))
        #expect(s.isVisible(["close-friends"], to: "close-friends"))
        #expect(!s.isVisible(["close-friends"], to: "acquaintances"))
        #expect(s.isVisible(["public"], to: "acquaintances"))
        #expect(!s.isVisible(["trip"], to: "family"))
        #expect(s.isVisible(["trip"], to: "trip"))
        #expect(!s.isVisible(["public"], to: "trip"))
        #expect(!s.isVisible([], to: "public"))
    }

    @Test func deletedAudienceSharesNothing() {
        var s = SharingSettings.defaults
        s.audiences[3].deleted_at = 5
        #expect(!s.isVisible(["public"], to: "public"))
        #expect(!s.isVisible(["public"], to: "family"))
    }

    @Test func newerFieldWinsTieKeepsServer() {
        var server = SharingSettings.defaults
        server.audiences[0].name = "Fam"
        server.audiences[0].clock.name = 100
        var local = SharingSettings.defaults
        local.audiences[0].name = "Family (old)"
        local.audiences[0].clock.name = 50
        local.audiences[0].location = "city"
        local.audiences[0].clock.location = 200

        let merged = server.merged(with: local)
        #expect(audience(merged, "family")?.name == "Fam")
        #expect(audience(merged, "family")?.location == "city")

        var tie = local
        tie.audiences[0].name = "Tie"
        tie.audiences[0].clock.name = 100
        #expect(audience(server.merged(with: tie), "family")?.name == "Fam")
    }

    @Test func listOnlyOneSideHasIsKept() {
        var local = SharingSettings.defaults
        local.audiences.append(.init(id: "japan-trip", name: "Japan trip", kind: "list", rank: nil, location: "city", color: nil, deleted_at: nil, clock: .init(name: 9)))
        let merged = SharingSettings.defaults.merged(with: local)
        #expect(audience(merged, "japan-trip")?.name == "Japan trip")
    }

    @Test func encodesNilsAsNullForTheWeb() throws {
        let data = try JSONEncoder().encode(SharingSettings.defaults)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let first = try #require((json["audiences"] as? [[String: Any]])?.first)
        #expect(first["deleted_at"] is NSNull)
        let back = try JSONDecoder().decode(SharingSettings.self, from: data)
        #expect(back == SharingSettings.defaults)
    }

    @Test func decodesTheWorkerReply() throws {
        let reply = #"{"audiences":[{"id":"family","name":"Family","kind":"circle","rank":1,"location":"exact","color":"#e0565b","deleted_at":null,"clock":{"name":0,"rank":0,"location":0,"color":0,"deleted_at":0}},{"id":"trip","name":"Trip","kind":"list","rank":null,"location":"city","color":null,"deleted_at":null,"clock":{"name":5,"rank":0,"location":5,"color":0,"deleted_at":0}}],"private_places":{"value":[{"name":"Home","words":["sukhumvit 31"],"lat":null,"lng":null,"radius_m":500}],"clock":7}}"#
        let s = try JSONDecoder().decode(SharingSettings.self, from: Data(reply.utf8))
        #expect(s.live.map(\.id) == ["family", "trip"])
        #expect(s.private_places.value.first?.words == ["sukhumvit 31"])
    }

    // MARK: Item.audiences on the wire

    @Test func itemAudiencesAreSortedAndUnique() {
        let item = Item(title: "x")
        item.audiences = ["public", "Family", "family"]
        #expect(item.audiences == ["family", "public"])
        item.audiences = []
        #expect(item.audiencesJSON == nil)
    }

    @Test func audiencesRoundTripOnTheWire() throws {
        let context = ModelContext(try StelloStore.makeInMemoryContainer())
        let item = Item(title: "x")
        context.insert(item)
        item.audiences = ["close-friends"]
        try context.save()
        #expect(SyncWire.values(of: item)["audiences"] as? [String] == ["close-friends"])

        var json = SyncWire.values(of: item)
        json["id"] = item.id.uuidString.lowercased()
        json["audiences"] = ["public", "family"]
        let data = try JSONSerialization.data(withJSONObject: json)
        let row = try #require(SyncWire.Row(try JSONSerialization.jsonObject(with: data) as! [String: Any]))
        SyncWire.apply(row, to: item, skipping: [])
        #expect(item.audiences == ["family", "public"])

        // A Worker without the field leaves the item alone.
        json.removeValue(forKey: "audiences")
        let old = try #require(SyncWire.Row(try JSONSerialization.jsonObject(with: try JSONSerialization.data(withJSONObject: json)) as! [String: Any]))
        SyncWire.apply(old, to: item, skipping: [])
        #expect(item.audiences == ["family", "public"])
    }

    @Test func audiencesChangeIsNamedInHistory() {
        #expect(SyncWire.fieldForKeyPath[\Item.audiencesJSON] == "audiences")
        #expect(SyncWire.allFields.contains("audiences"))
    }
}
