import Foundation
import SwiftData

@Model
final class Tag {
    var name: String = ""
    var category: String = ""
    var weight: Double = 0.5
    /// `rule` (capture), `ai` (enrichment), `manual` (user edits).
    var source: String = "rule"

    var item: Item?

    init(name: String = "", category: String = "", weight: Double = 0.5, source: String = "rule") {
        self.name = name
        self.category = category
        self.weight = weight
        self.source = source
    }
}
