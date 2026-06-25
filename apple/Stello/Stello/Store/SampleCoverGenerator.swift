import CoreGraphics
import Foundation
import ImageIO

/// Generates tasteful, deterministic procedural cover images for seed/sample items
/// so the masonry grid shows real image content with varied aspect ratios (matching
/// the web app's image-forward cards) without bundling binary assets or hitting the network.
enum SampleCoverGenerator {

    // Designer-ish palette pairs (top color -> bottom color), RGB 0...1.
    private static let palettes: [((Double, Double, Double), (Double, Double, Double))] = [
        ((0.10, 0.46, 0.43), (0.04, 0.16, 0.18)),   // teal -> deep teal
        ((0.96, 0.62, 0.20), (0.36, 0.18, 0.09)),   // amber -> umber
        ((0.36, 0.36, 0.84), (0.09, 0.10, 0.30)),   // iris -> navy
        ((0.86, 0.41, 0.38), (0.28, 0.10, 0.12)),   // coral -> maroon
        ((0.56, 0.70, 0.40), (0.15, 0.23, 0.12)),   // sage -> olive
        ((0.22, 0.24, 0.30), (0.06, 0.07, 0.10)),   // charcoal
        ((0.93, 0.86, 0.74), (0.55, 0.44, 0.31)),   // cream -> tan
        ((0.30, 0.55, 0.76), (0.07, 0.17, 0.30)),   // slate blue
        ((0.80, 0.52, 0.72), (0.30, 0.14, 0.28)),   // mauve
        ((0.95, 0.78, 0.30), (0.45, 0.30, 0.06)),   // mustard
    ]

    // Aspect ratios (width / height) — varied so the masonry has organic rhythm.
    private static let aspects: [Double] = [4.0/3.0, 3.0/4.0, 1.0, 16.0/9.0, 3.0/2.0, 2.0/3.0, 1.0, 4.0/5.0, 5.0/4.0]

    /// Deterministic cover for a seed (use a stable hash of the item slug).
    /// Returns PNG bytes plus pixel dimensions for the masonry aspect ratio.
    static func cover(seed: Int, width: Int = 640) -> (data: Data, width: Int, height: Int)? {
        let s = abs(seed)
        let palette = palettes[s % palettes.count]
        let aspect = aspects[(s / 7) % aspects.count]
        let w = width
        let h = max(1, Int((Double(width) / aspect).rounded()))

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Diagonal base gradient.
        let top = cgColor(palette.0, in: space)
        let bottom = cgColor(palette.1, in: space)
        if let grad = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: h),
                end: CGPoint(x: Double(w) * 0.35, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Soft off-center highlight for depth.
        let hx = Double(s * 13 % 100) / 100.0 * Double(w)
        let hy = Double(s * 29 % 100) / 100.0 * Double(h)
        let glowColors = [
            CGColor(colorSpace: space, components: [1, 1, 1, 0.16])!,
            CGColor(colorSpace: space, components: [1, 1, 1, 0])!,
        ]
        if let glow = CGGradient(colorsSpace: space, colors: glowColors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: hx, y: hy), startRadius: 0,
                endCenter: CGPoint(x: hx, y: hy), endRadius: Double(max(w, h)) * 0.65,
                options: []
            )
        }

        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, w, h)
    }

    /// Stable per-slug seed (String.hashValue is randomized per process, so we roll our own).
    static func stableSeed(_ slug: String) -> Int {
        slug.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
    }

    private static func cgColor(_ c: (Double, Double, Double), in space: CGColorSpace) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat(c.0), CGFloat(c.1), CGFloat(c.2), 1])!
    }
}
