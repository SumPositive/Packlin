//
//  M2Group.swift
//  PackList
//　　　 データ量的には3次元配列で十分だが、逐次保存など堅牢にするためにDBにする
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class M2Group {  // "Group"ではSwiftUI.Groupと競合するため"M2"を付与することになった。"M"はModel
    typealias ID = String
    @Attribute(.unique) var id: ID
    var order: Int

    var name: String
    var memo: String

    @Relationship(inverse: \M1Pack.child) var parent: M1Pack?
    @Relationship(deleteRule: .cascade) var child: [M3Item] = []

    var stock: Int { child.reduce(0) { $0 + $1.stock } }
    var need: Int { child.reduce(0) { $0 + $1.need } }

    var stockWeight: Int { child.reduce(0) { $0 + $1.weight * $1.stock } }
    var needWeight: Int { child.reduce(0) { $0 + $1.weight * $1.need } }

    init(id: ID = shortUUID(),
         name: String,
         memo: String = "",
         order: Int = 0,
         parent: M1Pack? = nil) {
        self.id = id
        self.name = name
        self.memo = memo
        self.order = order
        self.parent = parent
    }

    /// 子アイテムの order を連番に整理する
    func normalizeItemOrder() {
        let sorted = child.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }

        for (index, item) in sorted.enumerated() {
            item.order = index
        }

        child = sorted
    }

    /// 次の order 値を取得する
    func nextItemOrder() -> Int {
        (child.map { $0.order }.max() ?? -1) + 1
    }
}

