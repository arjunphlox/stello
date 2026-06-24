import Foundation
import SwiftData

@Model
final class Snippet {
    var text: String = ""
    var source: String = "manual"
    var addedAt: Date = Date.now

    var item: Item?

    init(text: String = "", source: String = "manual", addedAt: Date = .now) {
        self.text = text
        self.source = source
        self.addedAt = addedAt
    }
}
