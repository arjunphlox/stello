import SwiftUI
import SwiftData

/// Full-height right column panel — item detail OR a tool (filters / import / settings).
struct SidePanelView: View {
    let content: SidePanelContent
    let selectedItem: Item?
    let allItems: [Item]
    @Binding var selectedTagNames: Set<String>
    var onClose: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    var body: some View {
        Group {
            if content == .itemDetail {
                itemDetailPanel
            } else {
                toolPanel
            }
        }
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: StelloLayout.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StelloLayout.panelCornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }

    // MARK: - Item detail (cover bleeds to top; floating glass close)

    private var itemDetailPanel: some View {
        ZStack(alignment: .topTrailing) {
            panelBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Legibility scrim behind the floating close control
            RadialGradient(
                colors: [.black.opacity(0.28), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 72
            )
            .frame(width: 96, height: 96, alignment: .topTrailing)
            .allowsHitTesting(false)

            StelloGlassIconButton(
                systemName: "xmark",
                style: .circularGlass,
                label: "Close panel",
                action: onClose
            )
            .padding(.top, 12)
            .padding(.trailing, 12)
            .zIndex(1)
        }
    }

    // MARK: - Tool panels (header row + body)

    private var toolPanel: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().overlay(theme.border)
            panelBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(headerTitle)
                .font(.karst(.headline))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            StelloGlassIconButton(
                systemName: "xmark",
                style: .circularGlass,
                label: "Close panel",
                action: onClose
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.backgroundSubtle)
    }

    private var headerTitle: String {
        switch content {
        case .itemDetail:
            let t = selectedItem?.title ?? ""
            return t.isEmpty ? "Untitled" : t
        case .filters:  return "Filter by Tag"
        case .import:   return "Add Item"
        case .settings: return "Settings"
        case .none:     return ""
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var panelBody: some View {
        switch content {
        case .itemDetail:
            if let item = selectedItem {
                DetailView(item: item, embedsInPanel: true)
            } else {
                ContentUnavailableView("Select an item", systemImage: "photo.on.rectangle")
                    .foregroundStyle(theme.textSecondary)
            }
        case .filters:
            TagFilterContent(allItems: allItems, selectedTagNames: $selectedTagNames)
        case .import:
            CaptureContent(onComplete: onClose)
        case .settings:
            SettingsPanelContent()
        case .none:
            EmptyView()
        }
    }
}

/// Settings body for the side panel — theme + iCloud status + About.
struct SettingsPanelContent: View {
    @AppStorage(ThemeAppearancePreference.storageKey) private var rawMode: String = ThemeAppearancePreference.defaultMode
    @AppStorage("theme.accent") private var rawAccent: String = AccentColor.amber.rawValue
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
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

                Section("Sync") {
                    LabeledContent("iCloud") {
                        Text("Private database")
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    Text("Personal knowledge base")
                        .font(.karst(.caption))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, 24)
        }
    }
}
