import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cover image + horizontal thumbnail strip with PhotosPicker add control.
struct DetailImageStrip: View {
    @Bindable var item: Item
    var bleedsToTop: Bool = false
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context

    @State private var previewImageID: PersistentIdentifier?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isDropTargeted = false

    private static let placeholderHues: [Double] = [18, 80, 38, 140, 25, 45, 12, 100]

    private var images: [ItemImage] {
        (item.images ?? []).filter(\.hasRenderableCoverData)
    }

    private var displayedImage: ItemImage? {
        if let id = previewImageID,
           let match = images.first(where: { $0.persistentModelID == id }) {
            return match
        }
        return item.coverImage
    }

    private var placeholderHue: Double {
        let idx = abs(item.slug.hashValue) % Self.placeholderHues.count
        return Self.placeholderHues[idx] / 360.0
    }

    var body: some View {
        VStack(spacing: bleedsToTop ? 8 : 8) {
            mainImage
            thumbnailStrip
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentColor.opacity(0.85), lineWidth: 2)
            }
        }
        .onDrop(of: DropImportService.attachDropTypes, isTargeted: $isDropTargeted) { providers in
            DropImportService.attachToItem(item, from: providers, context: context)
        }
        .onChange(of: pickerItem) { _, new in
            guard let new else { return }
            Task { await loadPhoto(from: new) }
        }
    }

    // MARK: - Main image

    @ViewBuilder
    private var mainImage: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = displayedImage?.data, let img = platformImage(from: data) {
                img
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
            } else {
                Color(hue: placeholderHue,
                      saturation: 0.4,
                      brightness: theme.mode == .dark ? 0.26 : 0.88)
                    .frame(height: 160)
            }

            if let displayed = displayedImage,
               !displayed.isPrimary,
               displayed.hasRenderableCoverData {
                Button {
                    setAsCover(displayed)
                } label: {
                    Label("Set as cover", systemImage: "scope")
                        .font(.karst(.caption2, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    // MARK: - Thumbnail strip

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images, id: \.persistentModelID) { image in
                    thumbnailButton(for: image)
                }
                addImageControl
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func thumbnailButton(for image: ItemImage) -> some View {
        let isPreview = displayedImage?.persistentModelID == image.persistentModelID
        return Button {
            previewImageID = image.persistentModelID
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let data = image.data, let img = platformImage(from: data) {
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.borderSubtle)
                        .frame(width: 52, height: 52)
                }

                if image.isPrimary {
                    Circle()
                        .fill(theme.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isPreview ? theme.accentColor : theme.border, lineWidth: isPreview ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(image.isPrimary ? "Cover image" : "Image thumbnail")
    }

    private var addImageControl: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add")
                    .font(.karst(.caption2))
            }
            .foregroundStyle(theme.textSecondary)
            .frame(width: 52, height: 52)
            .background(theme.borderSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add image")
    }

    // MARK: - Mutations

    private func setAsCover(_ image: ItemImage) {
        for img in item.images ?? [] {
            img.isPrimary = img.persistentModelID == image.persistentModelID
        }
        previewImageID = image.persistentModelID
        item.updatedAt = .now
        try? context.save()
    }

    private func addImage(data: Data) {
        let (w, h) = CaptureService.imageDimensions(data: data)
        let needsPrimary = item.coverImage?.hasRenderableCoverData != true
        let img = ItemImage(data: data, source: "manual", isPrimary: needsPrimary, width: w, height: h)
        context.insert(img)
        img.item = item
        if item.images == nil { item.images = [] }
        item.images?.append(img)
        previewImageID = img.persistentModelID
        item.updatedAt = .now
        try? context.save()
    }

    private func loadPhoto(from pickerItem: PhotosPickerItem) async {
        defer {
            Task { @MainActor in self.pickerItem = nil }
        }
        guard let data = try? await pickerItem.loadTransferable(type: Data.self), !data.isEmpty else { return }
        await MainActor.run { addImage(data: data) }
    }

    private func platformImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #endif
    }
}
