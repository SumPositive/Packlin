import Foundation
import SwiftData

@Model
final class M3Item {
    var name: String
    var note: String
    var stock: Int
    var need: Int
    var weight: Double
    @Relationship(inverse: \M2Group.child) var parent: M2Group?

    var lack: Int { max(need - stock, 0) }

    init(name: String,
         note: String = "",
         stock: Int = 0,
         need: Int = 0,
         weight: Double = 0,
         parent: M2Group? = nil) {
        self.name = name
        self.note = note
        self.stock = stock
        self.need = need
        self.weight = weight
        self.parent = parent
    }
}
