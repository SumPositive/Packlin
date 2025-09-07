//
//  M2Group.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class M2Group {  // "Group"ではSwiftUI.Groupと競合するため"M2"を付与することになった。"M"はModel
    var name: String
    var memo: String
    var order: Int

    @Relationship(inverse: \M1Pack.child) var parent: M1Pack?
    @Relationship(deleteRule: .cascade) var child: [M3Item] = []

    var stock: Int { child.reduce(0) { $0 + $1.stock } }
    var need: Int { child.reduce(0) { $0 + $1.need } }

    var stockWeight: Int { child.reduce(0) { $0 + $1.weight * $1.stock } }
    var needWeight: Int { child.reduce(0) { $0 + $1.weight * $1.need } }

    init(name: String, memo: String = "", order: Int = 0, parent: M1Pack? = nil) {
        self.name = name
        self.memo = memo
        self.order = order
        self.parent = parent
    }
}

extension M2Group {
    typealias ID = PersistentIdentifier
    var id: ID { persistentModelID }
}

extension M2Group {
    /// 子アイテムの order を連番に整理する
    func normalizeItemOrder() {
        child = child.sorted { $0.order < $1.order }
        for (index, item) in child.enumerated() {
            item.order = index
        }
    }

    /// 次の order 値を取得する
    func nextItemOrder() -> Int {
        (child.map { $0.order }.max() ?? -1) + 1
    }
}

