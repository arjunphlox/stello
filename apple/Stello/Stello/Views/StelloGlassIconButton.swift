import SwiftUI

enum StelloGlassIconButtonStyle {
    /// Header / toolbar — rounded square with accent-contrast fill.
    case roundedSquare
    /// Panel overlay — 32pt circle with Liquid Glass.
    case circularGlass
    /// Bottom control bar — rounded square matching the floating search glass.
    case controlBar
    /// Bottom control bar — circular avatar matching the floating search glass.
    case controlBarAvatar
}

/// Uniform icon button — shared by header and panel chrome.
/// Matches web `.header-btn` (32×32, 8pt radius, accent-contrast tint fill + border).
struct StelloGlassIconButton: View {
    let systemName: String
    var style: StelloGlassIconButtonStyle = .roundedSquare
    var isActive: Bool = false
    var contrastForeground: Bool = true
    var avatarImage: Image? = nil
    /// Screenshot fixture — forces hover highlight without cursor focus.
    var forceHover: Bool = false
    /// Control-bar circle diameter (defaults to 40pt).
    var controlBarDiameter: CGFloat = StelloLayout.controlBarButtonSize
    var controlBarSymbolSize: CGFloat = StelloLayout.iconButtonSymbolSize
    let label: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovered = false

    private var showsHover: Bool { isHovered || forceHover }

    private var squareShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StelloLayout.iconButtonCornerRadius, style: .continuous)
    }

    var body: some View {
        switch style {
        case .roundedSquare:
            Button(action: action) {
                iconLabel
                    .background { squareButtonBackground }
                    .contentShape(squareShape)
            }
            .buttonStyle(GlassIconPressStyle(showsPressedOverlay: false))
            .accessibilityLabel(label)
            .help(label)
            .applyGlassButtonHover($isHovered)
        case .circularGlass:
            Button(action: action) {
                iconLabel
                    .background { circularGlassBackground }
                    .contentShape(Circle())
            }
            .buttonStyle(GlassIconPressStyle(showsPressedOverlay: false))
            .accessibilityLabel(label)
            .help(label)
            .applyGlassButtonHover($isHovered)
        case .controlBar:
            Button(action: action) {
                controlBarIconLabel
                    .background { controlBarCircularBackground }
                    .contentShape(Circle())
            }
            .buttonStyle(GlassIconPressStyle(showsPressedOverlay: false))
            .accessibilityLabel(label)
            .help(label)
            .applyGlassButtonHover($isHovered)
        case .controlBarAvatar:
            Button(action: action) {
                controlBarIconLabel
                    .background { controlBarCircularBackground }
                    .contentShape(Circle())
            }
            .buttonStyle(GlassIconPressStyle(showsPressedOverlay: false))
            .accessibilityLabel(label)
            .help(label)
            .applyGlassButtonHover($isHovered)
        }
    }

    private var iconLabel: some View {
        Image(systemName: systemName)
            .font(.system(size: StelloLayout.iconButtonSymbolSize, weight: .medium))
            .foregroundStyle(foregroundStyle)
            .frame(width: StelloLayout.iconButtonFootprint, height: StelloLayout.iconButtonFootprint)
    }

    private var controlBarIconLabel: some View {
        Group {
            if style == .controlBarAvatar, let avatarImage {
                avatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: controlBarDiameter, height: controlBarDiameter)
                    .clipShape(Circle())
            } else {
                Image(systemName: systemName)
                    .font(.system(size: controlBarSymbolSize, weight: .medium))
                    .foregroundStyle(foregroundStyle)
                    .frame(width: controlBarDiameter, height: controlBarDiameter)
            }
        }
    }

    @ViewBuilder
    private var squareButtonBackground: some View {
        squareShape
            .fill(fillColor)
            .overlay(squareShape.stroke(borderColor, lineWidth: 1))
            .animation(.easeOut(duration: 0.12), value: showsHover)
            .animation(.easeOut(duration: 0.08), value: isActive)
    }

    @ViewBuilder
    private var circularGlassBackground: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .glassEffect(.regular.tint(theme.textPrimary.opacity(0.12)), in: Circle())
            .overlay(Circle().stroke(theme.textPrimary.opacity(showsHover ? 0.30 : 0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .animation(.easeOut(duration: 0.12), value: showsHover)
    }

    @ViewBuilder
    private var controlBarCircularBackground: some View {
        controlBarGlassBackground(in: Circle())
    }

    @ViewBuilder
    private func controlBarGlassBackground<S: InsettableShape>(in shape: S) -> some View {
        shape
            .fill(theme.surfaceRaised.opacity(controlBarFillOpacity))
            .overlay(shape.stroke(theme.border, lineWidth: 1))
            .glassEffect(.regular.interactive(), in: shape)
            .animation(.easeOut(duration: 0.12), value: showsHover)
            .animation(.easeOut(duration: 0.08), value: isActive)
    }

    private var controlBarFillOpacity: CGFloat {
        let base = StelloLayout.controlBarGlassFillOpacity
        if isActive {
            return min(base + 0.08, 0.72)
        }
        if showsHover {
            return min(base + 0.04, 0.68)
        }
        return base
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
        switch style {
        case .circularGlass, .controlBar, .controlBarAvatar:
            theme.textPrimary.opacity(isActive || showsHover ? 1 : 0.88)
        case .roundedSquare:
            if contrastForeground {
                theme.accentContrast.opacity(isActive || showsHover ? 1 : 0.75)
            } else {
                theme.textSecondary.opacity(isActive || showsHover ? 1 : 0.82)
            }
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

private extension View {
    @ViewBuilder
    func applyGlassButtonHover(_ isHovered: Binding<Bool>) -> some View {
        #if os(macOS)
        self
            .focusEffectDisabled()
            .onHover { isHovered.wrappedValue = $0 }
        #else
        self
        #endif
    }
}
