import UIKit
import SwiftUI
import SwiftData

@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareView>!

    override func viewDidLoad() {
        super.viewDidLoad()
        embed(phase: .saving)
        Task { await processSharedItems() }
    }

    // MARK: - Embed helper

    private func embed(phase: SharePhase) {
        let onCancel: () -> Void = { [weak self] in
            self?.extensionContext?.cancelRequest(
                withError: NSError(domain: "StelloShare", code: 0)
            )
        }
        if hostingController == nil {
            let view = ShareView(phase: phase, onCancel: onCancel)
            hostingController = UIHostingController(rootView: view)
            addChild(hostingController)
            self.view.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            ])
            hostingController.didMove(toParent: self)
        } else {
            hostingController.rootView = ShareView(phase: phase, onCancel: onCancel)
        }
    }

    // MARK: - Process shared items

    private func processSharedItems() async {
        guard let extensionCtx = extensionContext,
              let item = extensionCtx.inputItems.first as? NSExtensionItem else {
            embed(phase: .error("No content to save."))
            return
        }
        do {
            let container = try StelloStore.makeExtensionContainer()
            let context = ModelContext(container)
            guard let input = await loadInput(from: item) else {
                embed(phase: .error("Could not read shared content."))
                return
            }
            var savedTitle: String? = nil
            switch input {
            case .url(let url):
                try await CaptureService.captureURL(url, context: context)
                savedTitle = CaptureService.domain(from: url) ?? url.host ?? url.absoluteString
            case .text(let text):
                try CaptureService.captureText(text, context: context)
                savedTitle = String(text.prefix(60))
            case .image(let data):
                try CaptureService.captureImage(data, context: context)
            }
            embed(phase: .saved(title: savedTitle))
            try await Task.sleep(for: .seconds(1.2))
            extensionCtx.completeRequest(returningItems: nil)
        } catch {
            embed(phase: .error(error.localizedDescription))
        }
    }

    // MARK: - Load input

    private enum SharedInput {
        case url(URL)
        case text(String)
        case image(Data)
    }

    private func loadInput(from item: NSExtensionItem) async -> SharedInput? {
        guard let attachments = item.attachments else { return nil }

        // Prefer URL
        for provider in attachments where provider.canLoadObject(ofClass: NSURL.self) {
            if let url = try? await loadObject(provider, ofClass: NSURL.self) {
                return .url(url as URL)
            }
        }
        // Then image
        for provider in attachments where provider.canLoadObject(ofClass: UIImage.self) {
            if let image = try? await loadObject(provider, ofClass: UIImage.self),
               let data = image.pngData() {
                return .image(data)
            }
        }
        // Then plain text
        for provider in attachments where provider.canLoadObject(ofClass: NSString.self) {
            if let text = try? await loadObject(provider, ofClass: NSString.self) {
                return .text(text as String)
            }
        }
        return nil
    }

    private func loadObject<T: NSItemProviderReading>(
        _ provider: NSItemProvider,
        ofClass type: T.Type
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let object = object as? T {
                    continuation.resume(returning: object)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "StelloShare", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected shared item type."]
                    ))
                }
            }
        }
    }
}
