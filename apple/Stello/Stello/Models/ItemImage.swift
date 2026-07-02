import CoreGraphics
import Foundation
import ImageIO
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Model
final class ItemImage {
    @Attribute(.externalStorage) var data: Data?
    var source: String = "og"
    var isPrimary: Bool = false
    var width: Int?
    var height: Int?
    var label: String?
    /// `cover`, `specimen`, `graphic`, `gallery`, or `preview`.
    var role: String = "cover"

    var item: Item?

    init(
        data: Data? = nil,
        source: String = "og",
        isPrimary: Bool = false,
        width: Int? = nil,
        height: Int? = nil,
        label: String? = nil,
        role: String = "cover"
    ) {
        self.data = data
        self.source = source
        self.isPrimary = isPrimary
        self.width = width
        self.height = height
        self.label = label
        self.role = role
    }
}

extension ItemImage {
    /// Non-empty bytes that decode to a platform bitmap (guards external-storage faulting + corrupt rows).
    var hasRenderableCoverData: Bool {
        guard let data, !data.isEmpty else { return false }
        return CoverImageDecoder.canDecode(data)
    }
}

extension Item {
    /// Best cover for card/detail rendering — prefers primary images with renderable bytes.
    var coverImage: ItemImage? {
        let imgs = images ?? []
        if let primary = imgs.first(where: { $0.isPrimary && $0.hasRenderableCoverData }) { return primary }
        if let any = imgs.first(where: \.hasRenderableCoverData) { return any }
        return imgs.first(where: \.isPrimary) ?? imgs.first
    }

    var hasRenderableCover: Bool { coverImage?.hasRenderableCoverData == true }
}

/// Shared cover decode check for persistence tests and card rendering.
enum CoverImageDecoder {
    static func canDecode(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetStatus(source) == .statusComplete
            || CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}

/// Decoded grid thumbnails — avoids re-decoding full cover bytes on every masonry layout pass.
enum CoverImageCache {
    #if os(macOS)
    typealias PlatformImage = NSImage
    #else
    typealias PlatformImage = UIImage
    #endif

    private final class CacheBox: NSObject {
        let image: PlatformImage
        init(_ image: PlatformImage) { self.image = image }
    }

    private static let cache: NSCache<NSString, CacheBox> = {
        let c = NSCache<NSString, CacheBox>()
        c.countLimit = 200
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    static func platformImage(data: Data, cacheKey: String) -> PlatformImage? {
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key)?.image { return cached }
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        #else
        guard let image = UIImage(data: data) else { return nil }
        #endif
        cache.setObject(CacheBox(image), forKey: key, cost: data.count)
        return image
    }
}
