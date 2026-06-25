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
        VStack(spacing: 0) {
            panelHeader
            Divider().overlay(theme.border)
            panelBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: StelloLayout.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StelloLayout.panelCornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                if content == .itemDetail, let domain = selectedItem?.domain, !domain.isEmpty {
                    Text(domain)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            StelloGlassIconButton(
                systemName: "xmark",
                contrastForeground: false,
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
                DetailView(item: item, embedInPanel: true)
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
    @AppStorage("theme.mode")   private var rawMode:   String = ColorMode.dark.rawValue
    @AppStorage("theme.accent") private var rawAccent: String = AccentColor.amber.rawValue
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
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

                Section("Sync") {
                    LabeledContent("iCloud") {
                        Text("Private database")
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    Text("Personal knowledge base")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, 24)
        }
    }
}
