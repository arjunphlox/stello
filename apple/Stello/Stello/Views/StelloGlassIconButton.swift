import SwiftUI

/// Uniform Liquid Glass capsule icon button — shared by header and panel chrome.
struct StelloGlassIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var contrastForeground: Bool = true
    let label: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: StelloLayout.iconButtonSymbolSize, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: StelloLayout.iconButtonFootprint, height: StelloLayout.iconButtonFootprint)
                .contentShape(Capsule())
        }
        .buttonStyle(GlassIconPressStyle())
        .glassEffect(
            isActive ? .regular.interactive().tint(theme.accentColor.opacity(0.35)) : .regular.interactive(),
            in: .capsule
        )
        .opacity(isHovered ? 1 : 0.92)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(label)
        .help(label)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
    }

    private var foregroundStyle: Color {
        if contrastForeground {
            theme.accentContrast.opacity(isActive || isHovered ? 1 : 0.82)
        } else {
            theme.textSecondary.opacity(isActive || isHovered ? 1 : 0.82)
        }
    }
}

private struct GlassIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
