import Foundation

/// Keeps the preferences header (name, designation, photo) the same here and on the
/// web, as part of each `SyncBridge` cycle. Field by field, whichever side changed it
/// last wins; the server applies the same rule (src/lib/profile.js), so an older edit
/// never overwrites a newer one even when two devices sync at once.
@MainActor
enum ProfileSync {
    static func sync(api: SyncAPI) async throws {
        let store = UserProfileStore.shared
        var server = try await api.profile()
        let sc = server.clock ?? .init()

        // Text: send what's newer here, take what's newer there.
        var fields: [String: String] = [:]
        var clock: [String: Int] = [:]
        switch decide(local: store.nameClock, server: sc.name, localEmpty: store.name.isEmpty, serverEmpty: server.name.isEmpty) {
        case .push: fields["name"] = store.name; clock["name"] = store.nameClock
        case .pull: store.applyRemote(name: server.name, nameClock: sc.name)
        case .none: break
        }
        switch decide(local: store.designationClock, server: sc.designation, localEmpty: store.designation.isEmpty, serverEmpty: server.designation.isEmpty) {
        case .push: fields["designation"] = store.designation; clock["designation"] = store.designationClock
        case .pull: store.applyRemote(designation: server.designation, designationClock: sc.designation)
        case .none: break
        }
        if !fields.isEmpty { server = try await api.putProfile(fields, clock: clock) }

        // Photo.
        switch decide(local: store.avatarClock, server: sc.avatar, localEmpty: !store.hasAvatar, serverEmpty: server.avatar_path == nil) {
        case .push:
            if store.hasAvatar, let data = try? Data(contentsOf: UserProfileStore.avatarFileURL) {
                let saved = try await api.uploadAvatar(data, contentType: SyncBridge.contentType(of: data), clock: store.avatarClock)
                store.avatarRemotePath = saved.avatar_path
            } else {
                _ = try await api.deleteAvatar(clock: store.avatarClock)
                store.avatarRemotePath = nil
            }
        case .pull:
            if let path = server.avatar_path {
                if path != store.avatarRemotePath {
                    let data = try await api.downloadImage(path: path)
                    store.applyRemoteAvatar(data, path: path, clock: sc.avatar)
                } else {
                    store.applyRemoteAvatar(try? Data(contentsOf: UserProfileStore.avatarFileURL), path: path, clock: sc.avatar)
                }
            } else {
                store.applyRemoteAvatar(nil, path: nil, clock: sc.avatar)
            }
        case .none:
            break
        }
    }

    enum Direction: Equatable { case push, pull, none }

    /// Newer side wins. On a tie (both never edited, clock 0) a value fills an empty side.
    nonisolated static func decide(local: Int, server: Int, localEmpty: Bool, serverEmpty: Bool) -> Direction {
        if local > server { return .push }
        if server > local { return .pull }
        if localEmpty, !serverEmpty { return .pull }
        return .none
    }
}
