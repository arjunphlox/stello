import SwiftUI

// MARK: - Mode & Accent

enum ColorMode: String, CaseIterable {
    case light, dark
}

/// Stored `theme.mode` values; `"system"` follows the device appearance.
enum ThemeAppearancePreference {
    static let storageKey = "theme.mode"
    static let system = "system"
    static let defaultMode = ColorMode.dark.rawValue

    static func resolvedColorMode(rawMode: String, systemScheme: ColorScheme) -> ColorMode {
        switch rawMode {
        case ColorMode.light.rawValue: .light
        case ColorMode.dark.rawValue:  .dark
        default:                        systemScheme == .dark ? .dark : .light
        }
    }

    static func preferredColorScheme(rawMode: String, theme: AppTheme) -> ColorScheme? {
        rawMode == system ? nil : theme.colorScheme
    }
}

enum AccentColor: String, CaseIterable {
    case lime, amber, iris

    /// Swatch hex for the picker dot (step-9, same both modes).
    var swatchColor: Color {
        switch self {
        case .lime:  Color(hex: "#bdee63")
        case .amber: Color(hex: "#ffc53d")
        case .iris:  Color(hex: "#5b5bd6")
        }
    }

    /// Fixed contrast text color for accent-9 backgrounds (do NOT derive from step-12).
    var contrastHex: String {
        switch self {
        case .lime:  "#37401c"
        case .amber: "#4f3422"
        case .iris:  "#ffffff"
        }
    }
}

// MARK: - Radix palette (12 steps + alpha-3)

struct RadixPalette {
    private let steps: [Color]
    let a3: Color

    init(steps: [Color], a3: Color = .clear) {
        self.steps = steps
        self.a3 = a3
    }

    /// 1-based step access.
    subscript(step: Int) -> Color { steps[step - 1] }
}

// MARK: - Palette literals (verbatim from DESIGN_TOKENS.md)

private enum Palettes {
    // Sand
    static let sandLight = RadixPalette(steps: [
        Color(hex: "#fdfdfc"), Color(hex: "#f9f9f8"), Color(hex: "#f1f0ef"),
        Color(hex: "#e9e8e6"), Color(hex: "#e2e1de"), Color(hex: "#dad9d6"),
        Color(hex: "#cfceca"), Color(hex: "#bcbbb5"), Color(hex: "#8d8d86"),
        Color(hex: "#82827c"), Color(hex: "#63635e"), Color(hex: "#21201c")
    ])
    static let sandDark = RadixPalette(steps: [
        Color(hex: "#111110"), Color(hex: "#191918"), Color(hex: "#222221"),
        Color(hex: "#2a2a28"), Color(hex: "#31312e"), Color(hex: "#3b3a37"),
        Color(hex: "#494844"), Color(hex: "#62605b"), Color(hex: "#6f6d66"),
        Color(hex: "#7c7b74"), Color(hex: "#b5b3ad"), Color(hex: "#eeeeec")
    ])

    // Lime
    static let limeLight = RadixPalette(steps: [
        Color(hex: "#fcfdfa"), Color(hex: "#f8faf3"), Color(hex: "#eef6d6"),
        Color(hex: "#e2f0bd"), Color(hex: "#d3e7a6"), Color(hex: "#c2da91"),
        Color(hex: "#abc978"), Color(hex: "#8db654"), Color(hex: "#bdee63"),
        Color(hex: "#b0e64c"), Color(hex: "#5c7c2f"), Color(hex: "#37401c")
    ], a3: Color(hex: "#96c80029"))
    static let limeDark = RadixPalette(steps: [
        Color(hex: "#11130c"), Color(hex: "#151a10"), Color(hex: "#1f2917"),
        Color(hex: "#29371d"), Color(hex: "#334423"), Color(hex: "#3d522a"),
        Color(hex: "#496231"), Color(hex: "#577538"), Color(hex: "#bdee63"),
        Color(hex: "#d4ff70"), Color(hex: "#bde56c"), Color(hex: "#e3f7ba")
    ], a3: Color(hex: "#9bfd4c1a"))

    // Amber (default)
    static let amberLight = RadixPalette(steps: [
        Color(hex: "#fefdfb"), Color(hex: "#fefbe9"), Color(hex: "#fff7c2"),
        Color(hex: "#ffee9c"), Color(hex: "#fbe577"), Color(hex: "#f3d673"),
        Color(hex: "#e9c162"), Color(hex: "#e2a336"), Color(hex: "#ffc53d"),
        Color(hex: "#ffba18"), Color(hex: "#ab6400"), Color(hex: "#4f3422")
    ], a3: Color(hex: "#ffde003d"))
    static let amberDark = RadixPalette(steps: [
        Color(hex: "#16120c"), Color(hex: "#1d180f"), Color(hex: "#302008"),
        Color(hex: "#3f2700"), Color(hex: "#4d3000"), Color(hex: "#5c3d05"),
        Color(hex: "#714f19"), Color(hex: "#8f6424"), Color(hex: "#ffc53d"),
        Color(hex: "#ffd60a"), Color(hex: "#ffca16"), Color(hex: "#ffe7b3")
    ], a3: Color(hex: "#fa820022"))

    // Iris
    static let irisLight = RadixPalette(steps: [
        Color(hex: "#fdfdff"), Color(hex: "#f8f8ff"), Color(hex: "#f0f1fe"),
        Color(hex: "#e6e7ff"), Color(hex: "#dadcff"), Color(hex: "#cbcdff"),
        Color(hex: "#b8baf8"), Color(hex: "#9b9ef0"), Color(hex: "#5b5bd6"),
        Color(hex: "#5151cd"), Color(hex: "#5753c6"), Color(hex: "#272962")
    ], a3: Color(hex: "#0011ee0f"))
    static let irisDark = RadixPalette(steps: [
        Color(hex: "#13131e"), Color(hex: "#171625"), Color(hex: "#202248"),
        Color(hex: "#262a65"), Color(hex: "#303374"), Color(hex: "#3d3e82"),
        Color(hex: "#4a4a95"), Color(hex: "#5958b1"), Color(hex: "#5b5bd6"),
        Color(hex: "#6e6ade"), Color(hex: "#b1a9ff"), Color(hex: "#e0dffe")
    ], a3: Color(hex: "#525bff3b"))
}

// MARK: - AppTheme

struct AppTheme: Equatable {
    var mode: ColorMode
    var accent: AccentColor

    init(mode: ColorMode = .dark, accent: AccentColor = .amber) {
        self.mode = mode
        self.accent = accent
    }

    private var sand: RadixPalette { mode == .dark ? Palettes.sandDark : Palettes.sandLight }
    private var accentPalette: RadixPalette {
        switch (accent, mode) {
        case (.lime,  .dark):  Palettes.limeDark
        case (.lime,  .light): Palettes.limeLight
        case (.amber, .dark):  Palettes.amberDark
        case (.amber, .light): Palettes.amberLight
        case (.iris,  .dark):  Palettes.irisDark
        case (.iris,  .light): Palettes.irisLight
        }
    }

    // Sand-based surface tokens
    var background:       Color { mode == .light ? Color(hex: "#f2f1ee") : sand[1] }
    var backgroundSubtle: Color { sand[2] }
    var surfaceRaised:    Color { sand[3] }
    var borderSubtle:     Color { sand[4] }
    var border:           Color { sand[6] }
    var textSecondary:    Color { sand[11] }
    var textPrimary:      Color { sand[12] }

    // Accent tokens
    var accentColor:    Color { accentPalette[9] }
    var accentHover:    Color { accentPalette[10] }
    var accentSubtle:   Color { accentPalette.a3 }
    var accentContrast: Color { Color(hex: accent.contrastHex) }

    var colorScheme: ColorScheme { mode == .dark ? .dark : .light }
}

// MARK: - Environment key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme()
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Color hex init (RRGGBB or RRGGBBAA)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch h.count {
        case 8: (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
