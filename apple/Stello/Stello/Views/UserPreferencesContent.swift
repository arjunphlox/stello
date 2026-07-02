import SwiftUI
import PhotosUI

/// Shared User Preferences body — profile row, appearance, and optional sections.
struct UserPreferencesContent: View {
    @AppStorage(ThemeAppearancePreference.storageKey) private var rawMode: String = ThemeAppearancePreference.defaultMode
    @AppStorage("theme.accent") private var rawAccent: String = AccentColor.amber.rawValue
    @AppStorage("stello.gridColumns") private var gridColumns: Int = 0

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var systemScheme
    @Environment(UserProfileStore.self) private var profile

    var showsGridSection: Bool = false
    var showsSyncSection: Bool = false
    var showsAboutSection: Bool = false

    private var resolvedMode: ColorMode {
        ThemeAppearancePreference.resolvedColorMode(rawMode: rawMode, systemScheme: systemScheme)
    }

    private var gridColumnsLabel: String {
        gridColumns == 0 ? "Auto" : "\(gridColumns) columns"
    }

    var body: some View {
        Form {
            Section {
                ProfileHeaderRow()
            }

            Section("Appearance") {
                Picker("Mode", selection: $rawMode) {
                    Text("System").tag(ThemeAppearancePreference.system)
                    Text("Light").tag(ColorMode.light.rawValue)
                    Text("Dark").tag(ColorMode.dark.rawValue)
                }
                .pickerStyle(.segmented)

                AccentColorPickerRow(
                    rawAccent: $rawAccent,
                    mode: resolvedMode
                )
            }

            if showsGridSection {
                Section("Grid") {
                    Stepper(gridColumnsLabel, value: $gridColumns, in: 0...12)
                    Text("Pinch the grid to zoom, or set columns here.")
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            if showsSyncSection {
                Section("Sync") {
                    LabeledContent("iCloud") {
                        Text("Private database")
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }

            if showsAboutSection {
                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    Text("Personal knowledge base")
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Profile header

private struct ProfileHeaderRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(UserProfileStore.self) private var profile

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ProfileAvatarPicker(
                pickerItem: $pickerItem,
                revision: profile.avatarRevision
            )
            VStack(alignment: .leading, spacing: 10) {
                InlineEditableProfileField(
                    value: Binding(
                        get: { profile.name },
                        set: { profile.name = $0 }
                    ),
                    placeholder: "Your name",
                    font: .karst(.title3, weight: .semibold),
                    color: theme.textPrimary
                )
                InlineEditableProfileField(
                    value: Binding(
                        get: { profile.designation },
                        set: { profile.designation = $0 }
                    ),
                    placeholder: "Designation",
                    font: .karst(.subheadline),
                    color: theme.textSecondary
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .onChange(of: pickerItem) { _, item in
            Task { await profile.loadAvatar(from: item) }
        }
    }
}

private struct ProfileAvatarPicker: View {
    @Binding var pickerItem: PhotosPickerItem?
    var revision: Int

    @Environment(\.appTheme) private var theme
    @Environment(UserProfileStore.self) private var profile
    @State private var isHovered = false

    private let size: CGFloat = 80

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                avatarContent
                overlayAffordance
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile picture")
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .id(revision)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let image = profile.avatarImage() {
            image
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(theme.backgroundSubtle)
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(theme.textSecondary.opacity(0.55))
                }
                .overlay {
                    Circle()
                        .stroke(theme.border, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var overlayAffordance: some View {
        #if os(macOS)
        if isHovered {
            Circle()
                .fill(.black.opacity(0.38))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
        #else
        Circle()
            .strokeBorder(theme.background, lineWidth: 2)
            .background(alignment: .bottomTrailing) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.accentColor)
                    .background(Circle().fill(theme.background))
                    .offset(x: 4, y: 4)
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        #endif
    }
}

// MARK: - Inline editable field

private struct InlineEditableProfileField: View {
    @Binding var value: String
    let placeholder: String
    let font: Font
    let color: Color

    @Environment(\.appTheme) private var theme
    @FocusState private var isFocused: Bool
    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField(placeholder, text: $draft)
                    .font(font)
                    .foregroundStyle(color)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { confirmEdit() }
                Button(action: confirmEdit) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Confirm")
            } else {
                Text(displayText)
                    .font(font)
                    .foregroundStyle(value.isEmpty ? color.opacity(0.55) : color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEdit() }
            }
        }
    }

    private var displayText: String {
        value.isEmpty ? placeholder : value
    }

    private func beginEdit() {
        draft = value
        isEditing = true
        isFocused = true
    }

    private func confirmEdit() {
        value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        isFocused = false
    }
}

// MARK: - Accent picker

struct AccentColorPickerRow: View {
    @Binding var rawAccent: String
    let mode: ColorMode

    @Environment(\.appTheme) private var theme

    private var choices: [AccentColor] {
        AccentColor.choices(for: mode)
    }

    var body: some View {
        HStack {
            Text("Accent")
            Spacer()
            HStack(spacing: 14) {
                ForEach(choices, id: \.rawValue) { accent in
                    Button {
                        rawAccent = accent.rawValue
                    } label: {
                        ZStack {
                            Circle()
                                .fill(accent.swatchColor(for: mode))
                                .frame(width: 22, height: 22)
                            if rawAccent == accent.rawValue {
                                Circle()
                                    .strokeBorder(theme.textPrimary, lineWidth: 2)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.displayName)
                }
            }
        }
    }
}

#Preview("User Preferences — dark") {
    UserPreferencesContent(showsGridSection: true, showsAboutSection: true)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .environment(UserProfileStore.shared)
        .preferredColorScheme(.dark)
        .padding()
}

#Preview("User Preferences — light") {
    UserPreferencesContent(showsAboutSection: true)
        .environment(\.appTheme, AppTheme(mode: .light, accent: .iris))
        .environment(UserProfileStore.shared)
        .preferredColorScheme(.light)
        .padding()
}
