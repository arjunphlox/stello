import Foundation

// Audience sharing on the Apple apps (docs/plans/audience-sharing.md). The settings
// shape and merge rule match the web's src/lib/sharing.js exactly: audiences are
// nested circles (rank 1 = innermost) plus standalone lists, every field carries an
// epoch-ms clock, and the newer clock wins (ties keep the server's value).
// Which items each audience gets lives on the item (`Item.audiences`), synced with
// the library. Share links live only on the web; see `SyncAPI.shareLinks()`.

nonisolated struct SharingSettings: Codable, Equatable, Sendable {
    var audiences: [Audience]
    var private_places: PrivatePlaces

    nonisolated struct Audience: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        /// `circle` or `list`. Fixed once made.
        var kind: String
        /// Circles only: 1 = innermost (Family). Inner circles also see outer ones' items.
        var rank: Int?
        /// What viewers see of an item's place: `exact`, `city` or `hidden`.
        var location: String
        var color: String?
        var deleted_at: Int?
        var clock: Clock

        nonisolated struct Clock: Codable, Equatable, Sendable {
            var name = 0, rank = 0, location = 0, color = 0, deleted_at = 0
        }

        // Nil goes out as null (not left out), so clearing a colour or restoring a
        // deleted audience reaches the web.
        private enum CodingKeys: String, CodingKey { case id, name, kind, rank, location, color, deleted_at, clock }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(kind, forKey: .kind)
            try c.encode(rank, forKey: .rank)
            try c.encode(location, forKey: .location)
            try c.encode(color, forKey: .color)
            try c.encode(deleted_at, forKey: .deleted_at)
            try c.encode(clock, forKey: .clock)
        }

        var isCircle: Bool { kind == "circle" }
        var isLive: Bool { deleted_at == nil }
    }

    nonisolated struct PrivatePlaces: Codable, Equatable, Sendable {
        var value: [Place] = []
        var clock = 0
    }

    /// Home and other places never shown to any audience.
    nonisolated struct Place: Codable, Equatable, Sendable {
        var name: String
        var words: [String]
        var lat: Double?
        var lng: Double?
        var radius_m: Int
    }

    /// The four circles every account starts with. Same ids as the web, so every
    /// device seeds the same rows. Clock 0: any real edit wins.
    static let defaults = SharingSettings(audiences: [
        .init(id: "family", name: "Family", kind: "circle", rank: 1, location: "exact", color: "#e0565b", deleted_at: nil, clock: .init()),
        .init(id: "close-friends", name: "Close friends", kind: "circle", rank: 2, location: "city", color: "#e39a3b", deleted_at: nil, clock: .init()),
        .init(id: "acquaintances", name: "Acquaintances", kind: "circle", rank: 3, location: "city", color: "#4f9d69", deleted_at: nil, clock: .init()),
        .init(id: "public", name: "Public", kind: "circle", rank: 4, location: "hidden", color: "#4a7fd6", deleted_at: nil, clock: .init()),
    ], private_places: .init())

    /// Live audiences, circles by rank, then lists by name (the web's order).
    var live: [Audience] {
        audiences.filter(\.isLive).sorted {
            if $0.isCircle != $1.isCircle { return $0.isCircle }
            return $0.isCircle ? ($0.rank ?? 0) < ($1.rank ?? 0) : $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    /// Would a link for `audienceID` show an item shared with `itemAudiences`?
    /// Same rule as `isVisible` in src/lib/sharing.js.
    func isVisible(_ itemAudiences: [String], to audienceID: String) -> Bool {
        let byID = Dictionary(audiences.filter(\.isLive).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard let target = byID[audienceID] else { return false }
        return itemAudiences.contains { id in
            guard let a = byID[id] else { return false }
            if a.id == target.id { return true }
            return target.isCircle && a.isCircle && (a.rank ?? 0) >= (target.rank ?? .max)
        }
    }

    /// Field by field, the newer clock wins; on a tie `self` (the server side) keeps
    /// its value. Audiences only one side has are kept.
    func merged(with other: SharingSettings) -> SharingSettings {
        var out = self
        for theirs in other.audiences {
            guard let i = out.audiences.firstIndex(where: { $0.id == theirs.id }) else {
                out.audiences.append(theirs)
                continue
            }
            var mine = out.audiences[i]
            if theirs.clock.name > mine.clock.name { mine.name = theirs.name; mine.clock.name = theirs.clock.name }
            if theirs.clock.rank > mine.clock.rank { mine.rank = theirs.rank; mine.clock.rank = theirs.clock.rank }
            if theirs.clock.location > mine.clock.location { mine.location = theirs.location; mine.clock.location = theirs.clock.location }
            if theirs.clock.color > mine.clock.color { mine.color = theirs.color; mine.clock.color = theirs.clock.color }
            if theirs.clock.deleted_at > mine.clock.deleted_at { mine.deleted_at = theirs.deleted_at; mine.clock.deleted_at = theirs.clock.deleted_at }
            out.audiences[i] = mine
        }
        if other.private_places.clock > out.private_places.clock { out.private_places = other.private_places }
        return out
    }
}

// MARK: - Local copy

/// This device's copy of the audiences, kept in Application Support and in step with
/// the web through `AudienceSync` (each sync cycle). Edits stamp the field's clock.
@Observable
@MainActor
final class SharingStore {
    static let shared = SharingStore()

    private(set) var settings: SharingSettings

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "sharing.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(SharingSettings.self, from: data) {
            settings = SharingSettings.defaults.merged(with: saved)
        } else {
            settings = .defaults
        }
    }

    var live: [SharingSettings.Audience] { settings.live }

    func audience(_ id: String) -> SharingSettings.Audience? { settings.audiences.first { $0.id == id } }

    /// Takes the web's merged settings, keeping any local edit newer than it.
    func adopt(_ server: SharingSettings) {
        let next = server.merged(with: settings)
        guard next != settings else { return }
        settings = next
        save()
    }

    func rename(_ id: String, to name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !clean.isEmpty else { return }
        edit(id) { $0.name = clean; $0.clock.name = Self.now() }
    }

    func setLocation(_ id: String, _ location: String) {
        guard ["exact", "city", "hidden"].contains(location) else { return }
        edit(id) { $0.location = location; $0.clock.location = Self.now() }
    }

    func setRank(_ id: String, _ rank: Int) {
        edit(id) { a in
            guard a.isCircle, rank > 0 else { return }
            a.rank = rank
            a.clock.rank = Self.now()
        }
    }

    func setColor(_ id: String, _ color: String?) {
        edit(id) { $0.color = color; $0.clock.color = Self.now() }
    }

    func delete(_ id: String) {
        edit(id) { $0.deleted_at = Self.now(); $0.clock.deleted_at = Self.now() }
    }

    /// A new standalone list (circles are the four defaults, renamed or reordered).
    @discardableResult
    func addList(named name: String) -> SharingSettings.Audience {
        let now = Self.now()
        var clock = SharingSettings.Audience.Clock()
        clock.name = now
        clock.location = now
        let list = SharingSettings.Audience(
            id: UUID().uuidString.lowercased(), name: String(name.prefix(60)), kind: "list", rank: nil,
            location: "city", color: nil, deleted_at: nil, clock: clock
        )
        settings.audiences.append(list)
        save()
        return list
    }

    func setPrivatePlaces(_ places: [SharingSettings.Place]) {
        settings.private_places = .init(value: places, clock: Self.now())
        save()
    }

    private func edit(_ id: String, _ change: (inout SharingSettings.Audience) -> Void) {
        guard let i = settings.audiences.firstIndex(where: { $0.id == id }) else { return }
        change(&settings.audiences[i])
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    static func now() -> Int { SyncWire.ms(.now) }
}

// MARK: - Sync

/// Rides along at the end of each `SyncBridge` cycle, like `ProfileSync`. Sends the
/// whole local copy with its clocks; the Worker keeps the newer side of every field
/// and answers with the result, which this device then adopts. Unchanged settings
/// cost the Worker no write.
@MainActor
enum AudienceSync {
    static func sync(api: SyncAPI) async throws {
        let store = SharingStore.shared
        let server = try await api.putSharing(store.settings)
        store.adopt(server)
    }
}
