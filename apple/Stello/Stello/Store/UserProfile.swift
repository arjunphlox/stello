import SwiftUI
import PhotosUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Local profile storage (no accounts)

@Observable
@MainActor
final class UserProfileStore {
    static let shared = UserProfileStore()

    private enum Keys {
        static let name = "profile.name"
        static let designation = "profile.designation"
    }

    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: Keys.name) }
    }

    var designation: String {
        didSet { UserDefaults.standard.set(designation, forKey: Keys.designation) }
    }

    /// Bumped when avatar bytes change so views refresh.
    private(set) var avatarRevision = 0

    private init() {
        name = UserDefaults.standard.string(forKey: Keys.name) ?? ""
        designation = UserDefaults.standard.string(forKey: Keys.designation) ?? ""
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
        avatarRevision &+= 1
    }

    func clearAvatar() {
        try? FileManager.default.removeItem(at: Self.avatarFileURL)
        avatarRevision &+= 1
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
