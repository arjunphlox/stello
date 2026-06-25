#if os(macOS)
import AppKit
import SwiftUI

/// Applies hidden-title-bar chrome so the accent header can extend to the window top edge,
/// with traffic lights overlaid on the yellow bar (leading inset handled in `StelloHeaderView`).
struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configureWindow(for: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configureWindow(for: nsView) }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        if #available(macOS 15.0, *) {
            window.titlebarSeparatorStyle = .none
        }
    }
}
#endif
