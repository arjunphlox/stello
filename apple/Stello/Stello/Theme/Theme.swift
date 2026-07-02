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

enum AccentColor: String, CaseIterable, Codable {
    // Bright accents (dark mode picker)
    case amber, lime, yellow, grass, cyan, orange
    // Muted accents (light mode picker)
    case iris, violet, plum, indigo, teal, bronze

    /// Bright Radix step-9 accents shown in dark mode.
    static let brightChoices: [AccentColor] = [.amber, .lime, .yellow, .grass, .cyan, .orange]
    /// Muted/darker accents shown in light mode.
    static let mutedChoices: [AccentColor] = [.iris, .violet, .plum, .indigo, .teal, .bronze]

    static func choices(for mode: ColorMode) -> [AccentColor] {
        mode == .dark ? brightChoices : mutedChoices
    }

    static func defaultAccent(for mode: ColorMode) -> AccentColor {
        mode == .dark ? .amber : .iris
    }

    /// Returns a valid accent for `mode`, falling back to that mode's default when stored is out-of-set.
    static func resolved(storedRawValue: String, for mode: ColorMode) -> AccentColor {
        let stored = AccentColor(rawValue: storedRawValue)
        let valid = choices(for: mode)
        if let stored, valid.contains(stored) { return stored }
        return defaultAccent(for: mode)
    }

    var displayName: String {
        rawValue.capitalized
    }

    /// Picker dot — step-9 for the active mode's palette.
    func swatchColor(for mode: ColorMode) -> Color {
        Palettes.accent(self, mode: mode)[9]
    }

    /// Fixed contrast text color for accent-9 backgrounds (do NOT derive from step-12).
    var contrastHex: String {
        switch self {
        case .lime:   "#37401c"
        case .amber:  "#4f3422"
        case .yellow: "#473b1f"
        case .grass:  "#ffffff"
        case .cyan:   "#ffffff"
        case .orange: "#ffffff"
        case .iris:   "#ffffff"
        case .violet: "#ffffff"
        case .plum:   "#ffffff"
        case .indigo: "#ffffff"
        case .teal:   "#ffffff"
        case .bronze: "#43302b"
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

    // Yellow
    static let yellowLight = RadixPalette(steps: [
        Color(hex: "#fdfdf9"), Color(hex: "#fefce9"), Color(hex: "#fffab8"), Color(hex: "#fff394"),
        Color(hex: "#ffe770"), Color(hex: "#f3d768"), Color(hex: "#e4c767"), Color(hex: "#d5ae39"),
        Color(hex: "#ffe629"), Color(hex: "#ffdc00"), Color(hex: "#9e6c00"), Color(hex: "#473b1f")
    ], a3: Color(hex: "#ffee0047"))
    static let yellowDark = RadixPalette(steps: [
        Color(hex: "#14120b"), Color(hex: "#1b180f"), Color(hex: "#2d2305"), Color(hex: "#362b00"),
        Color(hex: "#433500"), Color(hex: "#524202"), Color(hex: "#665417"), Color(hex: "#836a21"),
        Color(hex: "#ffe629"), Color(hex: "#ffff57"), Color(hex: "#f5e147"), Color(hex: "#f6eeb4")
    ], a3: Color(hex: "#ffaa001e"))

    // Grass
    static let grassLight = RadixPalette(steps: [
        Color(hex: "#fbfefb"), Color(hex: "#f5fbf5"), Color(hex: "#e9f6e9"), Color(hex: "#daf1db"),
        Color(hex: "#c9e8ca"), Color(hex: "#b2ddb5"), Color(hex: "#94ce9a"), Color(hex: "#65ba74"),
        Color(hex: "#46a758"), Color(hex: "#3e9b4f"), Color(hex: "#2a7e3b"), Color(hex: "#203c25")
    ], a3: Color(hex: "#00970016"))
    static let grassDark = RadixPalette(steps: [
        Color(hex: "#0e1511"), Color(hex: "#141a15"), Color(hex: "#1b2a1e"), Color(hex: "#1d3a24"),
        Color(hex: "#25482d"), Color(hex: "#2d5736"), Color(hex: "#366740"), Color(hex: "#3e7949"),
        Color(hex: "#46a758"), Color(hex: "#53b365"), Color(hex: "#71d083"), Color(hex: "#c2f0c2")
    ], a3: Color(hex: "#70fe8c1b"))

    // Cyan
    static let cyanLight = RadixPalette(steps: [
        Color(hex: "#fafdfe"), Color(hex: "#f2fafb"), Color(hex: "#def7f9"), Color(hex: "#caf1f6"),
        Color(hex: "#b5e9f0"), Color(hex: "#9ddde7"), Color(hex: "#7dcedc"), Color(hex: "#3db9cf"),
        Color(hex: "#00a2c7"), Color(hex: "#0797b9"), Color(hex: "#107d98"), Color(hex: "#0d3c48")
    ], a3: Color(hex: "#00c2d121"))
    static let cyanDark = RadixPalette(steps: [
        Color(hex: "#0b161a"), Color(hex: "#101b20"), Color(hex: "#082c36"), Color(hex: "#003848"),
        Color(hex: "#004558"), Color(hex: "#045468"), Color(hex: "#12677e"), Color(hex: "#11809c"),
        Color(hex: "#00a2c7"), Color(hex: "#23afd0"), Color(hex: "#4ccce6"), Color(hex: "#b6ecf7")
    ], a3: Color(hex: "#00befd28"))

    // Orange
    static let orangeLight = RadixPalette(steps: [
        Color(hex: "#fefcfb"), Color(hex: "#fff7ed"), Color(hex: "#ffefd6"), Color(hex: "#ffdfb5"),
        Color(hex: "#ffd19a"), Color(hex: "#ffc182"), Color(hex: "#f5ae73"), Color(hex: "#ec9455"),
        Color(hex: "#f76b15"), Color(hex: "#ef5f00"), Color(hex: "#cc4e00"), Color(hex: "#582d1d")
    ], a3: Color(hex: "#ff9c0029"))
    static let orangeDark = RadixPalette(steps: [
        Color(hex: "#17120e"), Color(hex: "#1e160f"), Color(hex: "#331e0b"), Color(hex: "#462100"),
        Color(hex: "#562800"), Color(hex: "#66350c"), Color(hex: "#7e451d"), Color(hex: "#a35829"),
        Color(hex: "#f76b15"), Color(hex: "#ff801f"), Color(hex: "#ffa057"), Color(hex: "#ffe0c2")
    ], a3: Color(hex: "#fb6a0025"))

    // Violet
    static let violetLight = RadixPalette(steps: [
        Color(hex: "#fdfcfe"), Color(hex: "#faf8ff"), Color(hex: "#f4f0fe"), Color(hex: "#ebe4ff"),
        Color(hex: "#e1d9ff"), Color(hex: "#d4cafe"), Color(hex: "#c2b5f5"), Color(hex: "#aa99ec"),
        Color(hex: "#6e56cf"), Color(hex: "#654dc4"), Color(hex: "#6550b9"), Color(hex: "#2f265f")
    ], a3: Color(hex: "#4400ee0f"))
    static let violetDark = RadixPalette(steps: [
        Color(hex: "#14121f"), Color(hex: "#1b1525"), Color(hex: "#291f43"), Color(hex: "#33255b"),
        Color(hex: "#3c2e69"), Color(hex: "#473876"), Color(hex: "#56468b"), Color(hex: "#6958ad"),
        Color(hex: "#6e56cf"), Color(hex: "#7d66d9"), Color(hex: "#baa7ff"), Color(hex: "#e2ddfe")
    ], a3: Color(hex: "#8354fe36"))

    // Plum
    static let plumLight = RadixPalette(steps: [
        Color(hex: "#fefcff"), Color(hex: "#fdf7fd"), Color(hex: "#fbebfb"), Color(hex: "#f7def8"),
        Color(hex: "#f2d1f3"), Color(hex: "#e9c2ec"), Color(hex: "#deade3"), Color(hex: "#cf91d8"),
        Color(hex: "#ab4aba"), Color(hex: "#a144af"), Color(hex: "#953ea3"), Color(hex: "#53195d")
    ], a3: Color(hex: "#cc00cc14"))
    static let plumDark = RadixPalette(steps: [
        Color(hex: "#181118"), Color(hex: "#201320"), Color(hex: "#351a35"), Color(hex: "#451d47"),
        Color(hex: "#512454"), Color(hex: "#5e3061"), Color(hex: "#734079"), Color(hex: "#92549c"),
        Color(hex: "#ab4aba"), Color(hex: "#b658c4"), Color(hex: "#e796f3"), Color(hex: "#f4d4f4")
    ], a3: Color(hex: "#fd4cfd27"))

    // Indigo
    static let indigoLight = RadixPalette(steps: [
        Color(hex: "#fdfdfe"), Color(hex: "#f7f9ff"), Color(hex: "#edf2fe"), Color(hex: "#e1e9ff"),
        Color(hex: "#d2deff"), Color(hex: "#c1d0ff"), Color(hex: "#abbdf9"), Color(hex: "#8da4ef"),
        Color(hex: "#3e63dd"), Color(hex: "#3358d4"), Color(hex: "#3a5bc7"), Color(hex: "#1f2d5c")
    ], a3: Color(hex: "#0047f112"))
    static let indigoDark = RadixPalette(steps: [
        Color(hex: "#11131f"), Color(hex: "#141726"), Color(hex: "#182449"), Color(hex: "#1d2e62"),
        Color(hex: "#253974"), Color(hex: "#304384"), Color(hex: "#3a4f97"), Color(hex: "#435db1"),
        Color(hex: "#3e63dd"), Color(hex: "#5472e4"), Color(hex: "#9eb1ff"), Color(hex: "#d6e1ff")
    ], a3: Color(hex: "#2f62ff3c"))

    // Teal
    static let tealLight = RadixPalette(steps: [
        Color(hex: "#fafefd"), Color(hex: "#f3fbf9"), Color(hex: "#e0f8f3"), Color(hex: "#ccf3ea"),
        Color(hex: "#b8eae0"), Color(hex: "#a1ded2"), Color(hex: "#83cdc1"), Color(hex: "#53b9ab"),
        Color(hex: "#12a594"), Color(hex: "#0d9b8a"), Color(hex: "#008573"), Color(hex: "#0d3d38")
    ], a3: Color(hex: "#00c69d1f"))
    static let tealDark = RadixPalette(steps: [
        Color(hex: "#0d1514"), Color(hex: "#111c1b"), Color(hex: "#0d2d2a"), Color(hex: "#023b37"),
        Color(hex: "#084843"), Color(hex: "#145750"), Color(hex: "#1c6961"), Color(hex: "#207e73"),
        Color(hex: "#12a594"), Color(hex: "#0eb39e"), Color(hex: "#0bd8b6"), Color(hex: "#adf0dd")
    ], a3: Color(hex: "#00ffe61e"))

    // Bronze
    static let bronzeLight = RadixPalette(steps: [
        Color(hex: "#fdfcfc"), Color(hex: "#fdf7f5"), Color(hex: "#f6edea"), Color(hex: "#efe4df"),
        Color(hex: "#e7d9d3"), Color(hex: "#dfcdc5"), Color(hex: "#d3bcb3"), Color(hex: "#c2a499"),
        Color(hex: "#a18072"), Color(hex: "#957468"), Color(hex: "#7d5e54"), Color(hex: "#43302b")
    ], a3: Color(hex: "#92250015"))
    static let bronzeDark = RadixPalette(steps: [
        Color(hex: "#141110"), Color(hex: "#1c1917"), Color(hex: "#262220"), Color(hex: "#302a27"),
        Color(hex: "#3b3330"), Color(hex: "#493e3a"), Color(hex: "#5a4c47"), Color(hex: "#6f5f58"),
        Color(hex: "#a18072"), Color(hex: "#ae8c7e"), Color(hex: "#d4b3a5"), Color(hex: "#ede0d9")
    ], a3: Color(hex: "#faceb817"))

    static func accent(_ accent: AccentColor, mode: ColorMode) -> RadixPalette {
        switch (accent, mode) {
        case (.lime,   .dark):  limeDark
        case (.lime,   .light): limeLight
        case (.amber,  .dark):  amberDark
        case (.amber,  .light): amberLight
        case (.yellow, .dark):  yellowDark
        case (.yellow, .light): yellowLight
        case (.grass,  .dark):  grassDark
        case (.grass,  .light): grassLight
        case (.cyan,   .dark):  cyanDark
        case (.cyan,   .light): cyanLight
        case (.orange, .dark):  orangeDark
        case (.orange, .light): orangeLight
        case (.iris,   .dark):  irisDark
        case (.iris,   .light): irisLight
        case (.violet, .dark):  violetDark
        case (.violet, .light): violetLight
        case (.plum,   .dark):  plumDark
        case (.plum,   .light): plumLight
        case (.indigo, .dark):  indigoDark
        case (.indigo, .light): indigoLight
        case (.teal,   .dark):  tealDark
        case (.teal,   .light): tealLight
        case (.bronze, .dark):  bronzeDark
        case (.bronze, .light): bronzeLight
        }
    }
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
    private var accentPalette: RadixPalette { Palettes.accent(accent, mode: mode) }

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
