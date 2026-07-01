import SwiftUI

struct SettingsView: View {
    @AppStorage(ThemeAppearancePreference.storageKey) private var rawMode: String = ThemeAppearancePreference.defaultMode
    @AppStorage("theme.accent") private var rawAccent: String = AccentColor.amber.rawValue
    @AppStorage("stello.gridColumns") private var gridColumns: Int = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private var gridColumnsLabel: String {
        gridColumns == 0 ? "Auto" : "\(gridColumns) columns"
    }

    var body: some View {
        #if os(macOS)
        settingsForm
            .frame(minWidth: 320, minHeight: 160)
            .padding()
        #else
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(theme.accentColor)
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $rawMode) {
                    Text("System").tag(ThemeAppearancePreference.system)
                    Text("Light").tag(ColorMode.light.rawValue)
                    Text("Dark").tag(ColorMode.dark.rawValue)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Accent")
                    Spacer()
                    HStack(spacing: 14) {
                        ForEach(AccentColor.allCases, id: \.rawValue) { a in
                            Button { rawAccent = a.rawValue } label: {
                                ZStack {
                                    Circle()
                                        .fill(a.swatchColor)
                                        .frame(width: 22, height: 22)
                                    if rawAccent == a.rawValue {
                                        Circle()
                                            .strokeBorder(theme.textPrimary, lineWidth: 2)
                                            .frame(width: 28, height: 28)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Grid") {
                Stepper(gridColumnsLabel, value: $gridColumns, in: 0...12)
                Text("Pinch the grid to zoom, or set columns here.")
                    .font(.karst(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
}
