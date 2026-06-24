import Foundation
import SwiftData

@Model
final class Tag {
    var name: String = ""
    var category: String = ""
    var weight: Double = 0.5

    var item: Item?

    init(name: String = "", category: String = "", weight: Double = 0.5) {
        self.name = name
        self.category = category
        self.weight = weight
    }
}
