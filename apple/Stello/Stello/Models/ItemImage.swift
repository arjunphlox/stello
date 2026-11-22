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
    /// Where the image came from. `data` may be a small thumbnail of this.
    var sourceURL: String?
    /// Waiting for the import's cover pass. With no `sourceURL`, the pass reads the
    /// item's page to find one.
    var coverPending: Bool = false
    /// Where the web copy keeps these bytes (`/img/<key>` on the Stello Worker), once
    /// the sync bridge has uploaded them or matched them to an existing R2 image.
    var remotePath: String?

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
        // Import thumbnails were decoded when written; this runs for every card render.
        if sourceURL != nil { return true }
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

    /// The value `coverAspect` should hold. Matches how `ItemCardView` sizes its cover.
    var renderedCoverAspect: Double {
        guard let cover = coverImage, cover.hasRenderableCoverData else { return 0 }
        if let width = cover.width, let height = cover.height, width > 0, height > 0 {
            return Double(width) / Double(height)
        }
        return 1200.0 / 630.0
    }

    func refreshCoverAspect() {
        let aspect = renderedCoverAspect
        if coverAspect != aspect { coverAspect = aspect }
    }
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
        c.countLimit = 100
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    private final class DecodedBox: NSObject, @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Decoded bitmaps for grid cards. Cost is decoded bytes, so the limit is real memory.
    /// 64 MB holds a few screens of display-size covers; scrolling back past that
    /// re-decodes off the main thread.
    nonisolated private static let decoded: NSCache<NSString, DecodedBox> = {
        let cache = NSCache<NSString, DecodedBox>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// Empties both caches when the system reports memory pressure. Installed at launch.
    static let watchMemoryPressure: DispatchSourceMemoryPressure = {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { purge() } }
        source.resume()
        return source
    }()

    static func purge() {
        decoded.removeAllObjects()
        cache.removeAllObjects()
    }

    /// Long side in pixels for a cover shown `columnWidth` points wide: enough to fill
    /// the card at this scale, rounded up to steps of 200, at most 1200.
    nonisolated static func decodePixels(columnWidth: CGFloat, scale: CGFloat, aspect: CGFloat) -> Int {
        guard columnWidth > 0, scale > 0, aspect > 0 else { return 1200 }
        let long = columnWidth * scale * max(1, 1 / aspect)
        let stepped = Int((long / 200).rounded(.up)) * 200
        return min(max(stepped, 200), 1200)
    }

    nonisolated static func decodedImage(forKey key: String) -> CGImage? {
        decoded.object(forKey: key as NSString)?.image
    }

    /// Decodes off the main thread and keeps the bitmap, ready to draw. nil if the bytes
    /// aren't a readable image.
    /// Pixel size from the image header (orientation applied), without decoding pixels.
    nonisolated static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return nil }
        // EXIF orientations 5–8 swap width and height.
        if let o = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(o) { return (h, w) }
        return (w, h)
    }

    nonisolated static func decode(_ data: Data, key: String, maxPixels: Int = 1200) async -> CGImage? {
        if let cached = decodedImage(forKey: key) { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let image {
            decoded.setObject(DecodedBox(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
        }
        return image
    }

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
