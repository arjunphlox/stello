import SwiftUI

/// Uniform capsule icon button — shared by header and panel chrome.
/// macOS: visible hover/pressed fill; iOS: press scale.
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
                .background { hoverFill }
                .contentShape(Capsule())
        }
        .buttonStyle(GlassIconPressStyle())
        .glassEffect(
            isActive ? .regular.interactive().tint(theme.accentColor.opacity(0.35)) : .regular.interactive(),
            in: .capsule
        )
        .accessibilityLabel(label)
        .help(label)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
    }

    @ViewBuilder
    private var hoverFill: some View {
        #if os(macOS)
        Capsule()
            .fill(hoverFillColor)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isActive)
        #else
        EmptyView()
        #endif
    }

    #if os(macOS)
    private var hoverFillColor: Color {
        if isActive {
            return (contrastForeground ? theme.accentContrast : theme.textPrimary)
                .opacity(isHovered ? 0.22 : 0.14)
        }
        return (contrastForeground ? theme.accentContrast : theme.textPrimary)
            .opacity(isHovered ? 0.18 : 0)
    }
    #endif

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
            .opacity(configuration.isPressed ? 0.82 : 1)
            .overlay {
                #if os(macOS)
                if configuration.isPressed {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                }
                #endif
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
