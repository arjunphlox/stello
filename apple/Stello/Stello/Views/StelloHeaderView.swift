import SwiftUI

/// Accent-colored header mirroring the web app's `.header` — Stello wordmark, item tally,
/// and action buttons (Filters → Import → Settings).
struct StelloHeaderView: View {
    let itemCount: Int
    var hasActiveFilters: Bool = false
    var onFilters: () -> Void
    var onImport: () -> Void
    var onSettings: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Stello")
                    .font(.system(size: 48, weight: .regular))
                    .tracking(-1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.accentContrast.opacity(0.55))
                }
            }
            .foregroundStyle(theme.accentContrast)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                headerButton(
                    systemName: hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease",
                    isActive: hasActiveFilters,
                    label: "Filters",
                    action: onFilters
                )
                headerButton(systemName: "plus", label: "Import", action: onImport)
                headerButton(systemName: "gear", label: "Settings", action: onSettings)
            }
        }
        .padding(12)
        .frame(minHeight: 72, alignment: .bottom)
        .background(theme.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func headerButton(
        systemName: String,
        isActive: Bool = false,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .foregroundStyle(theme.accentContrast.opacity(isActive ? 1 : 0.75))
                .background(theme.accentContrast.opacity(isActive ? 0.20 : 0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.accentContrast.opacity(isActive ? 0.40 : 0.15), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    StelloHeaderView(itemCount: 19, hasActiveFilters: true, onFilters: {}, onImport: {}, onSettings: {})
        .padding()
        .background(Color(hex: "#111110"))
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
}
