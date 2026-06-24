import SwiftUI

enum ColorMode: String, CaseIterable {
    case light, dark
}

enum AccentColor: String, CaseIterable {
    case lime, amber, iris

    var color: Color {
        switch self {
        case .lime:  Color(red: 0.52, green: 0.80, blue: 0.10)
        case .amber: Color(red: 1.00, green: 0.75, blue: 0.02)
        case .iris:  Color(red: 0.40, green: 0.36, blue: 0.92)
        }
    }
}

struct AppTheme: Equatable {
    var mode: ColorMode = .light
    var accent: AccentColor = .lime
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme()
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
