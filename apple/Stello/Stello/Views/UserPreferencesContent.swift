import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import AuthenticationServices
import CryptoKit

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

            FolderSourcesSection()

            // The old web library import is gone (parity pass, Nov 22 2026): the
            // library is already in, and running it again could add duplicates.
            WebSyncSection()

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

// MARK: - Web library import

/// One-time import of the old web library (Supabase export JSON) into iCloud.
private struct WebLibraryImportSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var coordinator

    @State private var importer = WebLibraryImporter.shared
    @State private var pickingFile = false
    @State private var pilotOnly = true

    var body: some View {
        Section("Old web library") {
            Toggle("Test with 50 items first", isOn: $pilotOnly)
                .disabled(importer.isRunning)
            if importer.isRunning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(importer.statusText)
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    Button("Stop") { importer.cancel() }
                }
            } else {
                Button("Import export file…") { pickingFile = true }
                if !importer.statusText.isEmpty {
                    Text(importer.statusText)
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            if let stage = importer.stageText {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(stage)
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Text("Brings items from the old Stello web app into this library. Items appear right away; covers and kinds fill in while Stello is open, and AI summaries follow slowly or when you open an item.")
                .font(.karst(.caption))
                .foregroundStyle(theme.textSecondary)
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task {
                await importer.run(
                    fileURL: url,
                    context: context,
                    limit: pilotOnly ? 50 : nil
                )
                if !WebInboxProcessor.isDisabled {
                    await WebLibraryImporter.classifyPending(context: context, coordinator: coordinator)
                }
            }
        }
    }
}

// MARK: - Folders

/// The folders Stello reads and writes (folder engine plan 4b; web twin: Settings › Folders
/// in app.js). Add, Replace, Remove, and the one that takes new saves. The library still
/// comes from SwiftData; saves and edits are written to the folders beside it.
private struct FolderSourcesSection: View {
    @Environment(\.appTheme) private var theme
    @State private var sources = FolderSources.shared
    @State private var picking = false
    /// nil = adding a folder, else the folder being replaced.
    @State private var replacing: UUID?
    @State private var message: String?

    var body: some View {
        Section("Folders") {
            ForEach(sources.folders) { folder in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.karst(.body))
                            .foregroundStyle(theme.textPrimary)
                        Text(detail(folder))
                            .font(.karst(.caption))
                            .foregroundStyle(theme.textSecondary)
                        if sources.savesFolderID == folder.id {
                            Text("New saves go here")
                                .font(.karst(.caption))
                                .foregroundStyle(theme.accentColor)
                        }
                    }
                    Spacer(minLength: 8)
                    if folder.writable != true {
                        // Added before writes: the bookmark is read-only, so pick the folder once more.
                        Button("Allow writing") { replacing = folder.id; picking = true }
                            .buttonStyle(.borderless)
                            .foregroundStyle(theme.accentColor)
                    }
                    if sources.savesFolderID != folder.id, sources.folders.count > 1 {
                        Button("Use for new saves") { sources.setSavesFolder(folder.id) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(theme.accentColor)
                    }
                    Button("Replace") { replacing = folder.id; picking = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(theme.accentColor)
                    Button("Remove") {
                        sources.remove(folder.id)
                        message = "Folder removed. Its files are untouched."
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.textSecondary)
                }
            }
            Button("Add folder") { replacing = nil; picking = true }
            if let message {
                Text(message).font(.karst(.caption)).foregroundStyle(theme.textSecondary)
            }
            Text(sources.folders.isEmpty
                 ? "Add the folders your Stello items live in, such as iCloud Drive/Stello."
                 : "New saves and edits are written to these folders. Removing a folder only hides it here; its files stay as they are.")
                .font(.karst(.caption))
                .foregroundStyle(theme.textSecondary)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let outcome = replacing.map { sources.replace($0, with: url) } ?? sources.add(url: url)
            switch outcome {
            case .added: message = nil
            case .duplicate(let name): message = "\(name) is already added."
            case .covered(let name): message = "Already covered by \(name)."
            case .covers(let name): message = "That folder holds \(name), which is already added."
            case .failed: message = "Couldn’t open that folder."
            }
        }
    }

    private func detail(_ folder: FolderSources.Folder) -> String {
        switch sources.status[folder.id] ?? .ready {
        case .reading: return "Reading…"
        case .unreachable(let why): return why
        case .ready:
            let items = "\(folder.count.formatted()) item\(folder.count == 1 ? "" : "s")"
            let place = folder.displayPath.isEmpty ? "" : " · \(folder.displayPath)"
            return items + place
        }
    }
}

// MARK: - Web sync

/// Links this device to the Stello web account, so the web app gets its own copy of
/// the library (see `SyncBridge`).
private struct WebSyncSection: View {
    @Environment(\.appTheme) private var theme
    @State private var account = SyncAccount.shared
    @State private var nonce = ""

    var body: some View {
        Section("Web app") {
            if account.isSignedIn {
                LabeledContent("Stello account", value: "Signed in")
                Button("Sync now") { SyncBridge.requestSync(reason: "manual") }
                Button("Sign out of the web account", role: .destructive) { account.signOut() }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    nonce = Self.randomNonce()
                    request.requestedScopes = [.email]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    guard case .success(let auth) = result,
                          let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                          let token = credential.identityToken
                    else { return }
                    let raw = nonce
                    Task { await account.signIn(identityToken: token, nonce: raw) }
                }
                .frame(height: 36)
            }
            if let error = account.lastError {
                Text(error).font(.karst(.caption)).foregroundStyle(.red)
            }
            Text("Keeps a second copy of your library on the Stello web app, under the same Apple ID. Changes go both ways while Stello is open, and in the background on iPhone.")
                .font(.karst(.caption))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private static func randomNonce() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
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
                    font: .karst(.title3, weight: .medium),
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
