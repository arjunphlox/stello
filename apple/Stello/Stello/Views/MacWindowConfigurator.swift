#if os(macOS)
import AppKit
import SwiftUI

/// Transparent native title bar with traffic lights inset inside the header card (12pt).
/// Re-applies positioning on layout, resize, and fullscreen transitions.
struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeHostView {
        let view = WindowChromeHostView()
        view.onWindowChange = { window in
            WindowChromeController.shared.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowChromeHostView, context: Context) {
        if let window = nsView.window {
            WindowChromeController.shared.attach(to: window)
        }
    }
}

/// Configures window chrome and keeps traffic lights inset within the header card.
final class WindowChromeController {
    static let shared = WindowChromeController()

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func attach(to window: NSWindow) {
        configureWindow(window)
        repositionTrafficLights(in: window)
        guard self.window !== window else { return }
        detachObservers()
        self.window = window
        installObservers(for: window)
    }

    func repositionTrafficLights(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let titlebarContainer = close.superview else { return }

        for button in [close, mini, zoom] {
            button.isHidden = false
            button.alphaValue = 1
        }

        // Window inset reaches the header card edge; header padding is the 12pt gap inside the card.
        let inset = StelloLayout.windowInset + StelloLayout.headerPadding
        let buttonSize = close.frame.size
        let spacing = max(0, mini.frame.origin.x - close.frame.origin.x - buttonSize.width)
        let y = titlebarContainer.frame.height - inset - buttonSize.height
        var x = inset

        for button in [close, mini, zoom] {
            button.setFrameOrigin(NSPoint(x: x, y: y))
            x += buttonSize.width + spacing
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
        if #available(macOS 11.0, *) {
            window.toolbar?.displayMode = .iconOnly
        }
    }

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeScreenNotification,
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                guard let window = self?.window else { return }
                self?.repositionTrafficLights(in: window)
            }
            observers.append(observer)
        }
    }

    private func detachObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}

/// Notifies when attached to a window so title-bar chrome is configured after mount.
final class WindowChromeHostView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                self?.onWindowChange?(window)
            }
        }
    }

    override func layout() {
        super.layout()
        if let window {
            WindowChromeController.shared.repositionTrafficLights(in: window)
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        if let window {
            WindowChromeController.shared.repositionTrafficLights(in: window)
        }
    }
}
#endif
