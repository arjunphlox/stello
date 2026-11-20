import SwiftUI

/// Grid / Split / Canvas, beside the account button in the bottom bar (web #99).
/// Phones get Grid and Canvas only.
struct CanvasModeSwitch: View {
    var compactPhone = false
    /// Narrow bars: one round button showing the current mode, with a menu.
    var collapsed = false
    @Environment(\.appTheme) private var theme
    private var store: CanvasStore { .shared }

    private var modes: [CanvasViewMode] {
        compactPhone ? [.grid, .canvas] : CanvasViewMode.allCases
    }

    private var current: CanvasViewMode {
        compactPhone && store.viewMode == .split ? .canvas : store.viewMode
    }

    var body: some View {
        if collapsed { menuButton } else { segments }
    }

    private var menuButton: some View {
        let height = StelloLayout.controlBarHeight(compactPhone: compactPhone)
        return Menu {
            ForEach(modes) { mode in
                Button {
                    withAnimation(.smooth(duration: 0.25)) { store.viewMode = mode }
                } label: {
                    Label(mode.label, systemImage: mode.symbol)
                }
            }
        } label: {
            Image(systemName: current.symbol)
                .font(.system(size: StelloLayout.controlBarSymbolSize(compactPhone: compactPhone), weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: height, height: height)
                .background(theme.surfaceRaised.opacity(StelloLayout.controlBarGlassFillOpacity), in: Circle())
                .overlay(Circle().stroke(theme.border, lineWidth: 1))
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("View: \(current.label)")
    }

    private var segments: some View {
        let height = StelloLayout.controlBarHeight(compactPhone: compactPhone)
        return HStack(spacing: 2) {
            ForEach(modes) { mode in
                let on = current == mode
                Button {
                    withAnimation(.smooth(duration: 0.25)) { store.viewMode = mode }
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: StelloLayout.controlBarSymbolSize(compactPhone: compactPhone) - 2,
                                      weight: .medium))
                        .frame(width: height - 8, height: height - 8)
                        .background(on ? theme.accentColor : .clear, in: Circle())
                        .foregroundStyle(on ? theme.accentContrast : theme.textPrimary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(mode.label)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .frame(height: height)
        .background(theme.surfaceRaised.opacity(StelloLayout.controlBarGlassFillOpacity), in: Capsule())
        .overlay(Capsule().stroke(theme.border, lineWidth: 1))
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize()
    }
}

/// Bottom bar in Canvas mode: account, view switch, then zoom and Add at the right
/// (web #99: zoom sits at the far right; search and filter act on the grid).
struct CanvasBottomBar: View {
    var compactPhone = false
    let onAdd: () -> Void
    let onSettings: () -> Void

    @Environment(UserProfileStore.self) private var profile

    var body: some View {
        let size = StelloLayout.controlBarButtonDiameter(compactPhone: compactPhone)
        let symbol = StelloLayout.controlBarSymbolSize(compactPhone: compactPhone)
        HStack(spacing: StelloLayout.controlBarSpacing) {
            StelloGlassIconButton(
                systemName: "person.crop.circle.fill",
                style: .controlBarAvatar,
                avatarImage: profile.avatarImage(),
                controlBarDiameter: size,
                controlBarSymbolSize: symbol,
                label: "User Preferences",
                action: onSettings
            )
            .id(profile.avatarRevision)
            CanvasModeSwitch(compactPhone: compactPhone)
            CanvasDocBox(compactPhone: compactPhone)
            Spacer(minLength: 0)
            CanvasZoomPill()
            StelloGlassIconButton(
                systemName: "plus",
                style: .controlBar,
                controlBarDiameter: size,
                controlBarSymbolSize: symbol,
                label: "Add",
                action: onAdd
            )
        }
    }
}
