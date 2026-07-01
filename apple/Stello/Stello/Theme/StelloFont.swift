import CoreText
import SwiftUI

// MARK: - Karst registration + Font helpers

enum StelloFont {
    /// Bundled Karst OTF filenames → PostScript names (from fc-scan).
    static let postScriptNames: [String: String] = [
        "karst-light.otf": "Karst-Light",
        "karst-lightitalic.otf": "Karst-LightItalic",
        "karst-regular.otf": "Karst-Regular",
        "karst-regularitalic.otf": "Karst-RegularItalic",
        "karst-medium.otf": "Karst-Medium",
        "karst-mediumitalic.otf": "Karst-MediumItalic",
        "karst-semibold.otf": "Karst-SemiBold",
        "karst-semibolditalic.otf": "Karst-SemiBoldItalic",
        "karst-bold.otf": "Karst-Bold",
        "karst-bolditalic.otf": "Karst-BoldItalic",
    ]

    private static let fontsSubdirectory = "Resources/Fonts"

    /// Register all bundled Karst OTFs once at launch (iOS + macOS).
    static func registerBundledKarstFonts() {
        var urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil)?
            .filter { $0.lastPathComponent.hasPrefix("karst-") } ?? []
        if urls.isEmpty {
            urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: fontsSubdirectory) ?? []
        }
        guard !urls.isEmpty else {
            print("⚠️ StelloFont: no Karst OTF files found in bundle")
            return
        }

        for url in urls {
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !ok, let err = error?.takeRetainedValue() {
                print("⚠️ StelloFont registration (\(url.lastPathComponent)): \(err)")
            }
        }
    }

    static func postScriptName(weight: Font.Weight, italic: Bool) -> String {
        let base: String
        switch weight {
        case .ultraLight, .thin, .light:
            base = "Karst-Light"
        case .regular:
            base = "Karst-Regular"
        case .medium:
            base = "Karst-Medium"
        case .semibold:
            base = "Karst-SemiBold"
        case .bold, .heavy, .black:
            base = "Karst-Bold"
        default:
            base = "Karst-Regular"
        }
        guard italic else { return base }
        switch base {
        case "Karst-Light": return "Karst-LightItalic"
        case "Karst-Regular": return "Karst-RegularItalic"
        case "Karst-Medium": return "Karst-MediumItalic"
        case "Karst-SemiBold": return "Karst-SemiBoldItalic"
        default: return "Karst-BoldItalic"
        }
    }

    /// Semantic type scale — body = 14pt at default Dynamic Type; scales via `Font.karst(_:weight:)`.
    static func defaultSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 30
        case .title: return 24
        case .title2: return 20
        case .title3: return 17
        case .headline: return 15
        case .body: return 14
        case .callout: return 13
        case .subheadline: return 13
        case .footnote: return 12
        case .caption: return 11
        case .caption2: return 10
        @unknown default: return 14
        }
    }
}

extension Font {
    /// Fixed Karst size — use only for deliberate layout specs (wordmark, zoom curves, monograms).
    /// Prefer `.karst(.body)` (or `.caption`, `.headline`, etc.) for text that should track Dynamic Type.
    static func karst(size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        .custom(StelloFont.postScriptName(weight: weight, italic: italic), size: size)
    }

    /// Semantic Karst — 14pt body base, scales with Dynamic Type via `relativeTo:`.
    static func karst(_ style: Font.TextStyle, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        .custom(
            StelloFont.postScriptName(weight: weight, italic: italic),
            size: StelloFont.defaultSize(for: style),
            relativeTo: style
        )
    }
}
