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

    func scheduleEnrichment(for item: Item, context: ModelContext, force: Bool = false) {
        Task {
            await enrichItem(item, context: context, force: force)
        }
    }

    func enrichItem(_ item: Item, context: ModelContext, force: Bool = false) async {
        await EnrichmentService.enrich(item: item, context: context, enricher: activeEnricher, force: force)
        // A user-invoked Enrich must never silently no-op: when the system model reports
        // unavailable, the rule fallback runs and produces nothing — record WHY on the
        // item so the panel's error surface shows it (auto-enrichment stays quiet).
        if force,
           let foundationModels = primary as? FoundationModelsEnricher,
           let reason = foundationModels.unavailableReason {
            item.enrichmentError = "Apple Intelligence unavailable: \(reason)"
            item.updatedAt = .now
            try? context.save()
        }
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
    @MainActor static let defaultValue = EnrichmentCoordinator()
}

extension EnvironmentValues {
    var enrichmentCoordinator: EnrichmentCoordinator {
        get { self[EnrichmentCoordinatorKey.self] }
        set { self[EnrichmentCoordinatorKey.self] = newValue }
    }
}
