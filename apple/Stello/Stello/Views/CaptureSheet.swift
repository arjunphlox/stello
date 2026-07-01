import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Capture form — shared by the side panel (regular width) and `CaptureSheet` (iPhone).
/// Mirrors web `#tpl-import`: URL textarea, Import button, or-divider, file drop zone.
struct CaptureContent: View {
    var onComplete: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.enrichmentCoordinator) private var enrichmentCoordinator

    @State private var urlText = ""
    @State private var pickedPhoto: PhotosPickerItem? = nil
    @State private var isBusy = false
    @State private var isDropTargeted = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    "Paste URLs here, one per line…",
                    text: $urlText,
                    axis: .vertical
                )
                .lineLimit(5, reservesSpace: true)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .font(.karst(.subheadline))
                .padding(10)
                .background(theme.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Import URLs") {
                        Task { await commitURLs() }
                    }
                    .font(.karst(.subheadline, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.accentColor)
                    .foregroundStyle(theme.accentContrast)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                importDivider

                dropZone

                secondaryImageCapture

                if let msg = errorMessage {
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.karst(.caption))
                }
            }
            .padding(16)
        }
        .onChange(of: pickedPhoto) { _, item in
            guard item != nil else { return }
            Task { await capturePickedImage() }
        }
    }

    private var importDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.border).frame(height: 1)
            Text("or")
                .font(.karst(.caption))
                .foregroundStyle(theme.textSecondary)
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Text("Drop a CSV or Markdown file here")
                .font(.karst(.subheadline))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(isDropTargeted ? theme.accentSubtle : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? theme.accentColor : theme.border,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var secondaryImageCapture: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or pick an image")
                .font(.karst(.caption, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label("Choose Photo", systemImage: "photo")
            }
            .foregroundStyle(theme.accentColor)
        }
    }

    // MARK: - Actions

    private func finish() {
        if let onComplete { onComplete() }
        else { dismiss() }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                await importFile(at: url)
            }
        }
        return true
    }

    private func importFile(at url: URL) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            urlText = text
            await commitURLs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func captureImageData(_ data: Data) {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                let item = try CaptureService.captureImage(data, context: context)
                enrichmentCoordinator.scheduleEnrichment(for: item, context: context)
                finish()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func capturePickedImage() async {
        guard let item = pickedPhoto else { return }
        isBusy = true
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not load image data."
                isBusy = false
                return
            }
            let item = try CaptureService.captureImage(data, context: context)
            enrichmentCoordinator.scheduleEnrichment(for: item, context: context)
            finish()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func commitURLs() async {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        let inputs = CaptureService.classify(text: trimmed)
        do {
            for input in inputs {
                switch input {
                case .url(let url):
                    let item = try await CaptureService.captureURL(url, context: context)
                    enrichmentCoordinator.scheduleEnrichment(for: item, context: context)
                case .text(let t):
                    let item = try CaptureService.captureText(t, context: context)
                    enrichmentCoordinator.scheduleEnrichment(for: item, context: context)
                case .image(let d):
                    let item = try CaptureService.captureImage(d, context: context)
                    enrichmentCoordinator.scheduleEnrichment(for: item, context: context)
                }
            }
            finish()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }
}

struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            CaptureContent()
                .navigationTitle("Add Item")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

#Preview("Capture Sheet") {
    CaptureSheet()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
}
