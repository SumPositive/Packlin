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

        // 削除後に順序調整できるよう、親グループの識別子を退避する
        let parentGroupID = self.parent?.persistentModelID

        mc.delete(self)

        // 再フェッチしてchild配列から除かれた状態の親グループでorderを整理する
        if let parentGroupID {
            let descriptor = FetchDescriptor<M2Group>(
                predicate: #Predicate { element in
                    element.persistentModelID == parentGroupID
                }
            )
            if let reloadedParent = try? mc.fetch(descriptor).first {
                reloadedParent.normalizeItemOrder()
            }
        }
    }

    /// アイテム複製
    func duplicate() {
        guard let mc = modelContext else {return}
        guard let parent = self.parent else { return }
        let newItem = M3Item(name: self.name,
                             memo: self.memo,
                             check: false,
                             stock: 0,
                             need: self.need,
                             weight: self.weight,
                             order: self.order + 1, // 次(下)に追加
                             parent: parent)
        // DB追加
        mc.insert(newItem)
        // ReOrder
        parent.normalizeItemOrder()
    }

}

