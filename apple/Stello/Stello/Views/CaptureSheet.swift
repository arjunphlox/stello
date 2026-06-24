import SwiftUI
import SwiftData
import PhotosUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct CaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var inputText = ""
    @State private var pickedPhoto: PhotosPickerItem? = nil
    @State private var isBusy = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste a link, or type a note", text: $inputText, axis: .vertical)
                        .lineLimit(4, reservesSpace: false)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    Button("Paste from clipboard") {
                        pasteFromClipboard()
                    }
                    .foregroundStyle(theme.accentColor)
                }

                Section("Or pick an image") {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                    .foregroundStyle(theme.accentColor)
                }

                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Add") {
                            Task { await commit() }
                        }
                        .disabled(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && pickedPhoto == nil
                        )
                    }
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard item != nil else { return }
                Task { await capturePickedImage() }
            }
        }
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        #if os(iOS)
        if let img = UIPasteboard.general.image,
           let data = img.jpegData(compressionQuality: 0.9) {
            captureImageData(data)
            return
        }
        if let text = UIPasteboard.general.string { inputText = text }
        #else
        if let tiff = NSPasteboard.general.data(forType: .tiff) {
            captureImageData(tiff)
            return
        }
        if let text = NSPasteboard.general.string(forType: .string) { inputText = text }
        #endif
    }

    private func captureImageData(_ data: Data) {
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try CaptureService.captureImage(data, context: context)
                dismiss()
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
            try CaptureService.captureImage(data, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func commit() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        let inputs = CaptureService.classify(text: trimmed)
        do {
            for input in inputs {
                switch input {
                case .url(let url): try await CaptureService.captureURL(url, context: context)
                case .text(let t):  try CaptureService.captureText(t, context: context)
                case .image(let d): try CaptureService.captureImage(d, context: context)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }
}

#Preview("Capture Sheet") {
    CaptureSheet()
        .modelContainer(SeedData.previewContainer)
        .environment(\.appTheme, AppTheme(mode: .dark, accent: .amber))
        .preferredColorScheme(.dark)
}
