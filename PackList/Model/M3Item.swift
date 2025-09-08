//
//  M3Item.swift
//  PackList
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

    /// アイテムが展開されているか
    var isExpanded: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \M3Item.parentItem) var child: [M3Item] = []
    @Relationship(inverse: \M3Item.child) var parentItem: M3Item?
    @Relationship(inverse: \M2Group.child) var parent: M2Group?

    var lack: Int { max(need - stock, 0) }

    init(id: ID = shortUUID(),
         name: String,
         memo: String = "",
         check: Bool = false,
         stock: Int = 0,
         need: Int = 0,
         weight: Int = 0,
         order: Int = 0,
         parent: M2Group? = nil,
         parentItem: M3Item? = nil,
         isExpanded: Bool = false) {
        self.id = id
        self.name = name
        self.memo = memo
        self.check = check
        self.stock = stock
        self.need = need
        self.weight = weight
        self.order = order
        self.parent = parent
        self.parentItem = parentItem
        self.isExpanded = isExpanded
    }
}

