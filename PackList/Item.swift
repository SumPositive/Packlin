import Foundation
import SwiftData

@Model
final class Item {
    var name: String
    var note: String
    var stock: Int
    var need: Int
    var weight: Double
    @Relationship(inverse: \Group.child) var parent: Group?

    var lack: Int { max(need - stock, 0) }

    init(name: String,
         note: String = "",
         stock: Int = 0,
         need: Int = 0,
         weight: Double = 0,
         parent: Group? = nil) {
        self.name = name
        self.note = note
        self.stock = stock
        self.need = need
        self.weight = weight
        self.parent = parent
    }
}
