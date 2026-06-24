import SwiftUI

struct SettingsView: View {
    @AppStorage("theme.mode")   private var rawMode:   String = ColorMode.dark.rawValue
    @AppStorage("theme.accent") private var rawAccent: String = AccentColor.amber.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

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
        }
    }
}

#Preview {
    SettingsView()
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
}
