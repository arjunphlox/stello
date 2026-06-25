import SwiftUI

enum SharePhase {
    case saving
    case saved(title: String?)
    case error(String)
}

struct ShareView: View {
    let phase: SharePhase
    let onCancel: () -> Void

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
                        .font(.headline)

                case .saved(let title):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Saved ✓")
                        .font(.headline)
                    if let title {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("Couldn't Save")
                        .font(.headline)
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
}
