#if os(macOS)
import AppKit
import SwiftUI

/// Visual macOS traffic-light cluster inside the accent header — wired to the key window.
/// `standardWindowButton` repositioning is unreliable once SwiftUI paints a full-size
/// accent header under `fullSizeContentView`; replicas stay visible and centered.
struct MacTrafficLightCluster: View {
    var body: some View {
        HStack(spacing: 8) {
            trafficDot(color: Color(hex: "#FF5F57")) { NSApp.keyWindow?.performClose(nil) }
            trafficDot(color: Color(hex: "#FFBD2E")) { NSApp.keyWindow?.miniaturize(nil) }
            trafficDot(color: Color(hex: "#28C840")) { NSApp.keyWindow?.zoom(nil) }
        }
        .padding(.leading, 2)
    }

    private func trafficDot(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Window control")
    }
}
#endif
