import Foundation
import SwiftData

@Model
final class ItemImage {
    @Attribute(.externalStorage) var data: Data?
    var source: String = "og"
    var isPrimary: Bool = false
    var width: Int?
    var height: Int?
    var label: String?

    var item: Item?

    init(
        data: Data? = nil,
        source: String = "og",
        isPrimary: Bool = false,
        width: Int? = nil,
        height: Int? = nil,
        label: String? = nil
    ) {
        self.data = data
        self.source = source
        self.isPrimary = isPrimary
        self.width = width
        self.height = height
        self.label = label
    }
}
