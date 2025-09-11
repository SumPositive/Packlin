//
//  M1Pack.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftData

@Model
final class M1Pack {
    typealias ID = String
    @Attribute(.unique) var id: ID
    var order: Int

    var name: String
    var memo: String

    var createdAt: Date
    var pin: Bool

    @Relationship(deleteRule: .cascade) var child: [M2Group] = []

    var stock: Int { child.reduce(0) { $0 + $1.stock } }
    var need: Int { child.reduce(0) { $0 + $1.need } }

    var stockWeight: Int { child.reduce(0) { $0 + $1.stockWeight } }
    var needWeight: Int { child.reduce(0) { $0 + $1.needWeight } }

    init(id: ID = shortUUID(), name: String, memo: String = "", createdAt: Date = Date(), order: Int = 0, pin: Bool = false) {
        self.id = id
        self.name = name
        self.memo = memo
        self.createdAt = createdAt
        self.order = order
        self.pin = pin
    }
    
    /// 子グループの order を連番に整理する
    func normalizeGroupOrder() {
        child = child.sorted {
            if $0.pin == $1.pin {
                return $0.order < $1.order
            }
            return $0.pin && !$1.pin
        }
        for (index, group) in child.enumerated() {
            group.order = index
        }
    }

    /// 次のグループの order 値を取得する
    func nextGroupOrder() -> Int {
        (child.map { $0.order }.max() ?? -1) + 1
    }

    /// パック全体の order を連番に整理する
    static func normalizePackOrder(_ packs: [M1Pack]) {
        let sorted = packs.sorted {
            if $0.pin == $1.pin {
                return $0.order < $1.order
            }
            return $0.pin && !$1.pin
        }
        for (index, pack) in sorted.enumerated() {
            pack.order = index
        }
    }

    /// 次のパックの order 値を取得する
    static func nextPackOrder(_ packs: [M1Pack]) -> Int {
        (packs.map { $0.order }.max() ?? -1) + 1
    }
}

