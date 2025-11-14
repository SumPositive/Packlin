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
    /// - Note: order を唯一の真実源とする方針のため、child 配列の順序は変更しない。
    func normalizeItemOrder() {
        // order と id で安定ソートした配列に対してスパース再採番を適用する
        let sorted = child.sorted { ll, rr in
            if ll.order != rr.order {
                return ll.order < rr.order
            }
            return ll.id < rr.id
        }
        // 配列に触れず order のみを調整する
        normalizeSparseOrders(sorted)
    }

    /// 次の order 値を取得する
    func nextItemOrder() -> Int {
        let ordered = child.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            // 正規化時も order のみ操作する
            normalizeSparseOrders(ordered)
        }
    }
    
    /// 現在のGroupを削除する
    func delete() {
        guard let mc = modelContext else {return}
        // 親Packは削除後に順序調整するため、ここで一度退避しておく
        let parentPack = self.parent
        // groupの配下を削除
        for item in self.child {
            mc.delete(item)
        }
        // 自身を削除したあとで親側のorderを整理する
        mc.delete(self)
        // child配列からこのグループが消えた状態でorderを再計算させる
        parentPack?.normalizeGroupOrder()
    }

    /// 現在のGroupを複製して現在行下に追加する
    func duplicate() {
        guard let mc = modelContext else {return}
        guard let parent = self.parent else { return }
        // Groupを生成して追加する
        let newGroup = M2Group(name: self.name,
                               memo: self.memo,
                               order: self.order + 1,
                               parent: parent)
        mc.insert(newGroup)
        // Group配下のItemを複製する
        for item in self.child {
            // Itemを生成して追加する
            let newItem = M3Item(name: item.name,
                                 memo: item.memo,
                                 check: false,
                                 stock: 0,
                                 need: item.need,
                                 weight: item.weight,
                                 order: item.order,
                                 parent: newGroup)
            mc.insert(newItem)
        }
        // ReOrder
        parent.normalizeGroupOrder()
    }

}

