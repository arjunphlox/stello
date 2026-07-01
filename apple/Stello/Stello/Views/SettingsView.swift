import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        #if os(macOS)
        UserPreferencesContent(showsGridSection: true)
            .frame(minWidth: 360, minHeight: 280)
            .padding()
        #else
        NavigationStack {
            UserPreferencesContent(showsGridSection: true)
                .navigationTitle("User Preferences")
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
}

#Preview {
    SettingsView()
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .environment(UserProfileStore.shared)
        .preferredColorScheme(.dark)
}
