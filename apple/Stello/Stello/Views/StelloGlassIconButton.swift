import SwiftUI

/// Uniform capsule icon button — shared by header and panel chrome.
/// macOS: visible hover/pressed fill; iOS: press scale.
struct StelloGlassIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var contrastForeground: Bool = true
    /// Screenshot fixture — forces hover highlight without cursor focus.
    var forceHover: Bool = false
    let label: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovered = false

    private var showsHover: Bool { isHovered || forceHover }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: StelloLayout.iconButtonSymbolSize, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: StelloLayout.iconButtonFootprint, height: StelloLayout.iconButtonFootprint)
                .background { capsuleBackground }
                .overlay { capsuleBorder }
                .contentShape(Capsule())
        }
        .buttonStyle(GlassIconPressStyle(showsPressedOverlay: contrastForeground))
        .accessibilityLabel(label)
        .help(label)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
    }

    @ViewBuilder
    private var capsuleBackground: some View {
        Capsule()
            .fill(fillColor)
            .animation(.easeOut(duration: 0.12), value: showsHover)
            .animation(.easeOut(duration: 0.08), value: isActive)
    }

    @ViewBuilder
    private var capsuleBorder: some View {
        if contrastForeground {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var fillColor: Color {
        let base = contrastForeground ? theme.accentContrast : theme.textPrimary
        if isActive {
            return base.opacity(showsHover ? 0.22 : 0.18)
        }
        #if os(macOS)
        return base.opacity(showsHover ? 0.16 : 0.06)
        #else
        return base.opacity(showsHover ? 0.12 : 0)
        #endif
    }

    private var borderColor: Color {
        let base = theme.accentContrast
        if isActive {
            return base.opacity(0.38)
        }
        return base.opacity(showsHover ? 0.22 : 0.14)
    }

    private var foregroundStyle: Color {
        if contrastForeground {
            theme.accentContrast.opacity(isActive || showsHover ? 1 : 0.78)
        } else {
            theme.textSecondary.opacity(isActive || showsHover ? 1 : 0.82)
        }
    }
}

private struct GlassIconPressStyle: ButtonStyle {
    var showsPressedOverlay: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .overlay {
                #if os(macOS)
                if configuration.isPressed && showsPressedOverlay {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                }
                #endif
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
