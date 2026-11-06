#if DEBUG
import Darwin
import Foundation
import SwiftData

/// Proves the grid holds up at library scale: `-scaleCheck -screenshotCleanStore` fills the
/// in-memory store with 10,000 items, scrolls the real grid, and logs PASS or FAIL against
/// the budgets. Refuses to run without the in-memory flag, so it can't touch a real library.
@MainActor
enum ScaleCheck {
    static let itemCount = 10_000
    static let stallBudgetMs = 100.0
    static let memoryBudgetMB = 500.0
    static let refreshBudgetSeconds = 1.0

    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-scaleCheck") && arguments.contains("-screenshotCleanStore")
    }

    /// Set by the grid; scrolls to the given week key.
    static var scrollToWeek: ((String) -> Void)?
    /// Set by the grid; the week keys it knows about.
    static var weekKeys: (() -> [String])?
    /// How long the grid took to digest the full library.
    static var gridRefreshSeconds: Double?

    static func run(context: ModelContext) async {
        guard isEnabled else { return }
        seed(context: context)
        NSLog("SCALE seeded items=%d memoryMB=%.0f", itemCount, residentMemoryMB())
        try? await Task.sleep(for: .seconds(3))

        var stalls: [Double] = []
        var peakMemory = residentMemoryMB()
        let keys = weekKeys?() ?? []
        let stops = stride(from: 0, to: keys.count, by: max(keys.count / 60, 1)).map { keys[$0] }
        for key in stops + stops.reversed() {
            scrollToWeek?(key)
            for _ in 0..<4 {
                let start = ContinuousClock.now
                try? await Task.sleep(for: .milliseconds(50))
                let elapsed = ContinuousClock.now - start
                let (seconds, attoseconds) = elapsed.components
                stalls.append(Double(seconds) * 1000 + Double(attoseconds) / 1e15 - 50)
            }
            peakMemory = max(peakMemory, residentMemoryMB())
        }

        let sorted = stalls.sorted()
        let maxStall = sorted.last ?? 0
        let p95 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count) * 0.95)]
        let refresh = gridRefreshSeconds ?? -1
        let pass = !sorted.isEmpty && maxStall < stallBudgetMs && peakMemory < memoryBudgetMB
            && refresh >= 0 && refresh < refreshBudgetSeconds
        NSLog(
            "SCALE %@ stops=%d maxStallMs=%.0f p95StallMs=%.0f peakMemoryMB=%.0f gridRefreshS=%.2f",
            pass ? "PASS" : "FAIL", stops.count * 2, maxStall, p95, peakMemory, refresh
        )
    }

    private static func seed(context: ModelContext) {
        let covers = (0..<40).compactMap { SampleCoverGenerator.cover(seed: $0) }
        for index in 0..<itemCount {
            let item = Item(
                slug: "scale-\(index)", title: "Scale item \(index)",
                sourceURL: "https://example.com/\(index)", domain: "example.com",
                summary: "A summary long enough to count as real text for a card.",
                needsReview: false,
                addedAt: Date.now.addingTimeInterval(Double(-index) * 3_600),
                enrichmentStatus: "candidates_done"
            )
            item.tags = (0..<13).map { ItemTag(name: "tag-\($0)", category: "subject", source: "import") }
            context.insert(item)
            if index % 5 != 0, !covers.isEmpty {
                let cover = covers[index % covers.count]
                let image = ItemImage(data: cover.data, isPrimary: true, width: cover.width, height: cover.height)
                image.sourceURL = "https://example.com/\(index).png"
                context.insert(image)
                image.item = item
            }
            if index % 1_000 == 999 { try? context.save() }
        }
        try? context.save()
    }

    private static func residentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
#endif
