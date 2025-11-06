//
//  M3Item.swift
//  PackList
//　　　 データ量的には3次元配列で十分だが、逐次保存など堅牢にするためにDBにする
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class M3Item {
    typealias ID = String
    @Attribute(.unique) var id: ID
    var order: Int // 表示順

    var name: String
    var memo: String
    var check: Bool // チェック
    var stock: Int  // 在庫数
    var need: Int   // 必要数
    var weight: Int // 重量(g)

    @Relationship(inverse: \M2Group.child) var parent: M2Group?

    var lack: Int { max(need - stock, 0) }

    init(id: ID = shortUUID(),
         name: String,
         memo: String = "",
         check: Bool = false,
         stock: Int = 0,
         need: Int = 1,     // 初期1にした
         weight: Int = 0,
         order: Int = 0,
         parent: M2Group? = nil) {
        self.id = id
        self.name = name
        self.memo = memo
        self.check = check
        self.stock = stock
        self.need = need
        self.weight = weight
        self.order = order
        self.parent = parent
    }
    

    /// アイテム削除
    func delete() {
        guard let mc = modelContext else {return}
        // Undo grouping BEGIN
        mc.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            mc.undoManager?.groupingEnd()
        }
        
        if let group = self.parent {
//           let index = group.child.firstIndex(where: { $0.id == self.id }) {
//            group.child.remove(at: index)
            // ReOrder
            group.normalizeItemOrder()
        }
        mc.delete(self)
    }

    /// アイテム複製
    func duplicate() {
        guard let mc = modelContext else {return}
        // Undo grouping BEGIN
        mc.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            mc.undoManager?.groupingEnd()
        }
        guard let parent = self.parent else { return }
        let newItem = M3Item(name: self.name,
                             memo: self.memo,
                             stock: self.stock,
                             need: self.need,
                             weight: self.weight,
                             order: self.order + 1,
                             parent: parent)
        // DB追加
        mc.insert(newItem)
        // ReOrder
        parent.normalizeItemOrder()
    }

}

