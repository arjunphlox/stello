import SwiftUI
import PhotosUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Local profile storage

/// Name, designation and photo for the preferences header. Kept on this device and,
/// when signed in to the web account, in step with the web profile through
/// `ProfileSync` (per-field last write wins, like items).
@Observable
@MainActor
final class UserProfileStore {
    static let shared = UserProfileStore()

    enum Keys {
        static let name = "profile.name"
        static let designation = "profile.designation"
        /// When each field last changed on this device (or arrived from the web), epoch ms.
        static let nameClock = "profile.clock.name"
        static let designationClock = "profile.clock.designation"
        static let avatarClock = "profile.clock.avatar"
        /// The web's `/img/...` path for the photo on disk, so it's neither re-uploaded
        /// nor re-downloaded.
        static let avatarRemotePath = "profile.avatarRemotePath"
        static let clocksSeeded = "profile.clocksSeeded"
    }

    /// Set while applying web values, so they don't count as local edits.
    private var applyingRemote = false

    var name: String {
        didSet { saveText(name, key: Keys.name, clockKey: Keys.nameClock, changed: name != oldValue) }
    }

    var designation: String {
        didSet { saveText(designation, key: Keys.designation, clockKey: Keys.designationClock, changed: designation != oldValue) }
    }

    /// Bumped when avatar bytes change so views refresh.
    private(set) var avatarRevision = 0

    private init() {
        let d = UserDefaults.standard
        name = d.string(forKey: Keys.name) ?? ""
        designation = d.string(forKey: Keys.designation) ?? ""
        // A profile set up before syncing existed beats one the web saved before it had
        // clocks (clock 0), so this device's values go up on the first sync.
        if !d.bool(forKey: Keys.clocksSeeded) {
            if !name.isEmpty, d.object(forKey: Keys.nameClock) == nil { d.set(1, forKey: Keys.nameClock) }
            if !designation.isEmpty, d.object(forKey: Keys.designationClock) == nil { d.set(1, forKey: Keys.designationClock) }
            if hasAvatar, d.object(forKey: Keys.avatarClock) == nil { d.set(1, forKey: Keys.avatarClock) }
            d.set(true, forKey: Keys.clocksSeeded)
        }
    }

    private func saveText(_ value: String, key: String, clockKey: String, changed: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        guard changed, !applyingRemote else { return }
        UserDefaults.standard.set(Self.nowMs, forKey: clockKey)
        SyncBridge.requestSync(reason: "profile edited")
    }

    nonisolated static var nowMs: Int { Int((Date.now.timeIntervalSince1970 * 1000).rounded()) }

    // MARK: Sync state

    var nameClock: Int { UserDefaults.standard.integer(forKey: Keys.nameClock) }
    var designationClock: Int { UserDefaults.standard.integer(forKey: Keys.designationClock) }
    var avatarClock: Int { UserDefaults.standard.integer(forKey: Keys.avatarClock) }

    var avatarRemotePath: String? {
        get { UserDefaults.standard.string(forKey: Keys.avatarRemotePath) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.avatarRemotePath) }
    }

    /// A newer value from the web: shown here without counting as a local edit.
    func applyRemote(name newName: String? = nil, designation newDesignation: String? = nil, nameClock: Int? = nil, designationClock: Int? = nil) {
        applyingRemote = true
        defer { applyingRemote = false }
        if let newName, let nameClock {
            name = newName
            UserDefaults.standard.set(nameClock, forKey: Keys.nameClock)
        }
        if let newDesignation, let designationClock {
            designation = newDesignation
            UserDefaults.standard.set(designationClock, forKey: Keys.designationClock)
        }
    }

    /// A newer photo from the web (`data` nil: the web removed it).
    func applyRemoteAvatar(_ data: Data?, path: String?, clock: Int) {
        if let data {
            try? data.write(to: Self.avatarFileURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: Self.avatarFileURL)
        }
        avatarRemotePath = path
        UserDefaults.standard.set(clock, forKey: Keys.avatarClock)
        avatarRevision &+= 1
    }

    private func avatarEdited() {
        avatarRemotePath = nil
        UserDefaults.standard.set(Self.nowMs, forKey: Keys.avatarClock)
        avatarRevision &+= 1
        SyncBridge.requestSync(reason: "profile photo edited")
    }

    static var avatarFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Stello", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("avatar.jpg")
    }

    var hasAvatar: Bool {
        FileManager.default.fileExists(atPath: Self.avatarFileURL.path)
    }

    func avatarImage() -> Image? {
        guard hasAvatar,
              let data = try? Data(contentsOf: Self.avatarFileURL),
              let platform = PlatformImage(data: data) else { return nil }
        return platform.swiftUIImage
    }

    func saveAvatar(_ data: Data) throws {
        try data.write(to: Self.avatarFileURL, options: .atomic)
        avatarEdited()
    }

    func clearAvatar() {
        try? FileManager.default.removeItem(at: Self.avatarFileURL)
        avatarEdited()
    }

    func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self) else { return }
        try? saveAvatar(data)
    }
}

// MARK: - Cross-platform image bridge

#if os(macOS)
private typealias PlatformImage = NSImage
#else
private typealias PlatformImage = UIImage
#endif

private extension PlatformImage {
    var swiftUIImage: Image {
        #if os(macOS)
        Image(nsImage: self)
        #else
        Image(uiImage: self)
        #endif
    }
}
