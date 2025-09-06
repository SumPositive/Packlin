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
    var name: String
    var memo: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var child: [M2Group] = []
    
//    var stock: Int { child.reduce(0) { $0 + $1.stock } }
//    var need: Int { child.reduce(0) { $0 + $1.need } }

    var stockWeight: Int { child.reduce(0) { $0 + $1.stockWeight } }
    var needWeight: Int { child.reduce(0) { $0 + $1.needWeight } }

    init(name: String, memo: String = "", createdAt: Date = Date()) {
        self.name = name
        self.memo = memo
        self.createdAt = createdAt
    }
    
}

extension M1Pack {
    typealias ID = PersistentIdentifier        // ← public で再エクスポート
    var id: ID { persistentModelID }           // ← public な id を用意（任意）
}

