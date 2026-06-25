#if os(macOS)
import AppKit
import SwiftUI

/// Applies hidden-title-bar chrome and positions traffic lights inside the inset accent header card.
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
        positionTrafficLights(in: window)
    }

    private func positionTrafficLights(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton) else { return }

        let inset = StelloLayout.windowInset
        let headerHeight = StelloLayout.macHeaderHeight
        let leading = inset + StelloLayout.macTrafficLightLeadingPadding

        // Title-bar buttons use window coordinates; content extends under the title bar.
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        let headerCenterY = window.frame.height - inset - headerHeight / 2
        let y = headerCenterY - close.frame.height / 2

        // Only reposition when drifted — avoids fighting user drags during live resize.
        let targets: [(NSButton, CGFloat)] = [
            (close, leading),
            (mini, leading + 20),
            (zoom, leading + 40),
        ]
        for (button, x) in targets where abs(button.frame.origin.x - x) > 0.5 || abs(button.frame.origin.y - y) > 0.5 {
            button.setFrameOrigin(NSPoint(x: x, y: y))
        }

        _ = titlebarHeight // reserved for future titlebar layout tweaks
    }
}

/// Notifies when attached to a window so traffic-light layout runs after SwiftUI mounts content.
final class TrafficLightAnchorView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChange?(window)
        }
    }

    override func layout() {
        super.layout()
        if let window {
            onWindowChange?(window)
        }
    }
}
#endif
