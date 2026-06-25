#if os(macOS)
import AppKit
import SwiftUI

/// Transparent native title bar — traffic-light buttons are repositioned inside the
/// inset accent header card on every layout / resize so they stay anchored.
struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightAnchorView {
        let view = TrafficLightAnchorView()
        view.onWindowChange = { window in
            TrafficLightLayout.configureWindow(window)
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: TrafficLightAnchorView, context: Context) {
        if let window = nsView.window {
            TrafficLightLayout.configureWindow(window)
            context.coordinator.attach(to: window)
            context.coordinator.reposition()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var positioner = TrafficLightPositioner()

        func attach(to window: NSWindow) {
            positioner.attach(to: window)
        }

        func reposition() {
            positioner.reposition()
        }
    }
}

// MARK: - Window chrome

enum TrafficLightLayout {
    /// Positions the standard close / minimize / zoom cluster inside the inset header card.
    static func apply(to window: NSWindow) {
        guard let contentView = window.contentView else { return }

        let roles: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = roles.compactMap { window.standardWindowButton($0) }
        guard let close = buttons.first else { return }

        let originX = StelloLayout.macTrafficLightOriginX
        let contentHeight = contentView.bounds.height
        let originY = contentHeight - StelloLayout.macTrafficLightOriginYInset - close.frame.height

        var x = originX
        for (index, button) in buttons.enumerated() {
            button.isHidden = false
            var frame = button.frame
            frame.origin = NSPoint(x: x, y: originY)
            button.setFrameOrigin(frame.origin)
            if index < buttons.count - 1 {
                x += frame.width + interButtonGap
            }
        }
    }

    static func configureWindow(_ window: NSWindow) {
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
        apply(to: window)
    }

    private static let interButtonGap: CGFloat = 8
}

// MARK: - Re-apply on layout + resize

final class TrafficLightPositioner {
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func attach(to window: NSWindow) {
        if self.window === window, !observers.isEmpty { return }
        detach()
        self.window = window

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didUpdateNotification,
        ]
        for name in names {
            observers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.reposition()
                }
            )
        }
        reposition()
    }

    func detach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        window = nil
    }

    func reposition() {
        guard let window else { return }
        TrafficLightLayout.apply(to: window)
    }

    deinit {
        detach()
    }
}

/// Layout hook — repositions traffic lights whenever the host view lays out.
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

    override func layout() {
        super.layout()
        if let window {
            TrafficLightLayout.apply(to: window)
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        if let window {
            TrafficLightLayout.apply(to: window)
        }
    }
}
#endif
