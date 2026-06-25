#if os(macOS)
import AppKit
import SwiftUI

/// Transparent native title bar — real traffic-light buttons float at the system
/// position over content (Sketch-style). Content inset positions the header card
/// beneath them; never reposition the native buttons.
struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeHostView {
        let view = WindowChromeHostView()
        view.onWindowChange = { window in
            Self.configureWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowChromeHostView, context: Context) {
        if let window = nsView.window {
            Self.configureWindow(window)
        }
    }

    private static func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        if #available(macOS 15.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        if #available(macOS 11.0, *) {
            window.toolbar?.displayMode = .iconOnly
        }
        for role: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(role)?.isHidden = false
        }
    }
}

/// Notifies when attached to a window so title-bar chrome is configured after mount.
final class WindowChromeHostView: NSView {
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
