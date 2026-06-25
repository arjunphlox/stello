import Foundation
import SwiftData
import SwiftUI

@MainActor
final class EnrichmentCoordinator {
    let primary: Enricher
    let fallback: Enricher

    init(
        primary: Enricher = FoundationModelsEnricher(),
        fallback: Enricher = RuleBasedFallbackEnricher()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    private var activeEnricher: Enricher {
        primary.isAvailable ? primary : fallback
    }

    func scheduleEnrichment(for item: Item, context: ModelContext) {
        Task {
            await enrichItem(item, context: context)
        }
    }

    func enrichItem(_ item: Item, context: ModelContext) async {
        await EnrichmentService.enrich(item: item, context: context, enricher: activeEnricher)
    }

    func enrichPendingItems(context: ModelContext) async {
        let status = "text_done"
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.enrichmentStatus == status }
        )
        guard let items = try? context.fetch(descriptor) else { return }
        for item in items {
            await enrichItem(item, context: context)
        }
    }
}

// MARK: - Environment

private struct EnrichmentCoordinatorKey: EnvironmentKey {
    static let defaultValue = EnrichmentCoordinator()
}

extension EnvironmentValues {
    var enrichmentCoordinator: EnrichmentCoordinator {
        get { self[EnrichmentCoordinatorKey.self] }
        set { self[EnrichmentCoordinatorKey.self] = newValue }
    }
}
