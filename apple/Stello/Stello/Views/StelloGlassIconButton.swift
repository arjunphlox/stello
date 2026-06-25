import SwiftUI

/// Uniform Liquid Glass capsule icon button — shared by header and panel chrome.
struct StelloGlassIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var contrastForeground: Bool = true
    let label: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: StelloLayout.iconButtonSymbolSize, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: StelloLayout.iconButtonFootprint, height: StelloLayout.iconButtonFootprint)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(label)
        .help(label)
    }

    private var foregroundStyle: Color {
        if contrastForeground {
            theme.accentContrast.opacity(isActive ? 1 : 0.82)
        } else {
            theme.textSecondary.opacity(isActive ? 1 : 0.82)
        }
    }
}
