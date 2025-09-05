import Foundation
import SwiftData

@Model
final class M3Item {
    var name: String
    var note: String
    var check: Bool // チェック
    var stock: Int  // 在庫数
    var need: Int   // 必要数
    var weight: Int // 重量(g)

    @Relationship(inverse: \M2Group.child) var parent: M2Group?

    var lack: Int { max(need - stock, 0) }

    init(name: String,
         note: String = "",
         check: Bool = false,
         stock: Int = 0,
         need: Int = 0,
         weight: Int = 0,
         parent: M2Group? = nil) {
        self.name = name
        self.note = note
        self.check = check
        self.stock = stock
        self.need = need
        self.weight = weight
        self.parent = parent
    }
}

extension M3Item {
    typealias ID = PersistentIdentifier
    var id: ID { persistentModelID }
}
