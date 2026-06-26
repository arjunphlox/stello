import SwiftUI

/// Uniform rounded-square icon button — shared by header and panel chrome.
/// Matches web `.header-btn` (32×32, 8pt radius, accent-contrast tint fill + border).
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

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StelloLayout.iconButtonCornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: StelloLayout.iconButtonSymbolSize, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: StelloLayout.iconButtonFootprint, height: StelloLayout.iconButtonFootprint)
                .background { buttonBackground }
                .contentShape(buttonShape)
        }
        .buttonStyle(GlassIconPressStyle(showsPressedOverlay: false))
        .accessibilityLabel(label)
        .help(label)
        #if os(macOS)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        #endif
    }

    @ViewBuilder
    private var buttonBackground: some View {
        buttonShape
            .fill(fillColor)
            .overlay(buttonShape.stroke(borderColor, lineWidth: 1))
            .animation(.easeOut(duration: 0.12), value: showsHover)
            .animation(.easeOut(duration: 0.08), value: isActive)
    }

    private var fillColor: Color {
        let base = contrastForeground ? theme.accentContrast : theme.textPrimary
        if isActive {
            return base.opacity(showsHover ? 0.20 : 0.16)
        }
        #if os(macOS)
        return base.opacity(showsHover ? 0.16 : (contrastForeground ? 0.06 : 0))
        #else
        return base.opacity(showsHover ? 0.12 : 0)
        #endif
    }

    private var borderColor: Color {
        let base = contrastForeground ? theme.accentContrast : theme.textPrimary
        if isActive || (contrastForeground && showsHover) {
            return base.opacity(isActive ? 0.40 : 0.15)
        }
        return base.opacity(contrastForeground ? 0.15 : 0)
    }

    private var foregroundStyle: Color {
        if contrastForeground {
            theme.accentContrast.opacity(isActive || showsHover ? 1 : 0.75)
        } else {
            theme.textSecondary.opacity(isActive || showsHover ? 1 : 0.82)
        }
    }
}

private struct GlassIconPressStyle: ButtonStyle {
    var showsPressedOverlay: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
