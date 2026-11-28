import SwiftUI

enum SharePhase {
    case saving
    case saved(title: String?)
    case error(String)
}

struct ShareView: View {
    let phase: SharePhase
    let onCancel: () -> Void
    /// Canvases to offer after a web link is saved (empty: close on its own).
    var canvases: [SafariSaveInbox.CanvasEntry] = []
    var onCanvas: ((SafariSaveInbox.CanvasEntry) -> Void)? = nil
    var onDone: (() -> Void)? = nil
    @State private var picked: String?

    var body: some View {
        ZStack {
            Color.clear
                .background(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                switch phase {
                case .saving:
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Saving to Stello…")
                        .font(.headline.weight(.medium))

                case .saved(let title):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Saved ✓")
                        .font(.headline.weight(.medium))
                    if let title {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    if !canvases.isEmpty {
                        canvasRow
                    }

                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("Couldn't Save")
                        .font(.headline.weight(.medium))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                }
            }
            .padding(32)
        }
    }

    /// "Add to a canvas": one tap puts the saved link on that canvas too.
    private var canvasRow: some View {
        VStack(spacing: 12) {
            Text(picked.map { "Added to \($0)" } ?? "Add to a canvas")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(canvases, id: \.id) { canvas in
                        Button {
                            guard picked == nil else { return }
                            picked = canvas.name
                            onCanvas?(canvas)
                        } label: {
                            Text(canvas.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(picked == canvas.name ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.07),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: 420)
            Button("Done") { onDone?() }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        }
    }
}
