#if os(macOS)
import AppKit
import SwiftUI

/// Applies hidden-title-bar chrome; SwiftUI traffic-light replicas live in `MacTrafficLightCluster`.
struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightAnchorView {
        let view = TrafficLightAnchorView()
        view.onWindowChange = { window in
            configureWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: TrafficLightAnchorView, context: Context) {
        if let window = nsView.window {
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        if #available(macOS 15.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        for role: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(role)?.isHidden = true
        }
    }
}

/// Notifies when attached to a window so title-bar chrome is configured after mount.
final class TrafficLightAnchorView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                self?.onWindowChange?(window)
            }
        }
    }
}
#endif
