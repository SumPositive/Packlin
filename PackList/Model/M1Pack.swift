//
//  M1Pack.swift
//  PackList
//　　　 データ量的には3次元配列で十分だが、逐次保存など堅牢にするためにDBにする
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

    @Relationship(deleteRule: .cascade) var child: [M2Group] = []

    var stock: Int { child.reduce(0) { $0 + $1.stock } }
    var need: Int { child.reduce(0) { $0 + $1.need } }

    var stockWeight: Int { child.reduce(0) { $0 + $1.stockWeight } }
    var needWeight: Int { child.reduce(0) { $0 + $1.needWeight } }

    init(id: ID = shortUUID(),
         name: String,
         memo: String = "",
         createdAt: Date = Date(),
         order: Int = 0) {
        self.id = id
        self.name = name
        self.memo = memo
        self.createdAt = createdAt
        self.order = order
    }
    
    /// 子グループの order を連番に整理する
    /// - Note: 表示順は List 側で order を基準にソートするため、ここでは child 配列を書き換えない。
    ///         order だけを唯一の真実源として扱い、配列の順番は放置する。
    func normalizeGroupOrder() {
        // SwiftData の child 配列は順序が保証されないため、order と id で安定ソートしてから並べ替える
        let sorted = child.sorted { ll, rr in
            if ll.order != rr.order {
                return ll.order < rr.order
            }
            return ll.id < rr.id
        }
        // スパース間隔で再採番するが、child の並びはそのまま残す
        normalizeSparseOrders(sorted)
    }

    /// 次のグループの order 値を取得する
    func nextGroupOrder() -> Int {
        let ordered = child.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            // order だけを整えて child 配列には触れない
            normalizeSparseOrders(ordered)
        }
    }

    /// パック全体の order を連番に整理する
    static func normalizePackOrder(_ packs: [M1Pack]) {
        let sorted = packs.sorted { $0.order < $1.order }
        // 配列の並び順は呼び出し側で適切に反映する前提。ここでは order のみ更新する。
        normalizeSparseOrders(sorted)
    }

    /// 次のパックの order 値を取得する
    static func nextPackOrder(_ packs: [M1Pack]) -> Int {
        let ordered = packs.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            normalizeSparseOrders(ordered)
        }
    }
    
    /// 現在のPackを削除する
    func delete() {
        guard let mc = modelContext else {return}
        // groupとその配下を削除
        for group in self.child {
            group.delete()
        }
        // Packを削除
        mc.delete(self)
        // ReOrder
        let descriptor = FetchDescriptor<M1Pack>()
        if let packs = try? mc.fetch(descriptor) {
            M1Pack.normalizePackOrder(packs)
        }
    }
    
    /// 現在のPackを複製して現在行下に追加する
    func duplicate() {
        guard let mc = modelContext else {return}
        // createdAtは現在時刻とし、シート表示からの複製でもID重複や順序入れ替わりを避ける
        let newPack = M1Pack(name: self.name,
                             memo: self.memo,
                             createdAt: Date(),
                             order: self.order + 1)
        mc.insert(newPack)
        // Pack配下のGroupを複製する
        for group in self.child {
            // Groupを生成して追加する
            let newGroup = M2Group(name: group.name,
                                   memo: group.memo,
                                   order: group.order,
                                   parent: newPack)
            mc.insert(newGroup)
            // Group配下のItemを複製する
            for item in group.child {
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
        }
        // ReOrder
        let descriptor = FetchDescriptor<M1Pack>()
        if let packs = try? mc.fetch(descriptor) {
            M1Pack.normalizePackOrder(packs)
        }
    }
    
}

protocol SparseOrderable: AnyObject {
    var order: Int { get set }
}

extension M1Pack: SparseOrderable {}
extension M2Group: SparseOrderable {}
extension M3Item: SparseOrderable {}

/// スパース間隔で順序を振り直す。呼び出し側が順序付き配列を用意する前提。
func normalizeSparseOrders<T: SparseOrderable>(_ items: [T]) {
    for (index, element) in items.enumerated() {
        // index * ORDER_SPARSE_COUNT でベースラインを維持しつつ、挿入余地を確保する
        element.order = index * ORDER_SPARSE
    }
}

/// 指定した位置へ挿入する際のスパース order を算出する
func sparseOrderForInsertion<T: SparseOrderable>(
    items: [T],
    index: Int,
    normalize: () -> Void
) -> Int {
    let clampedIndex = max(0, min(index, items.count))
    return sparseOrderValue(
        previous: { 0 < clampedIndex ? items[clampedIndex - 1].order : nil },
        next: { clampedIndex < items.count ? items[clampedIndex].order : nil },
        normalize: normalize
    )
}

private func sparseOrderValue(
    previous: () -> Int?,
    next: () -> Int?,
    normalize: () -> Void
) -> Int {
    if let prev = previous(), let nextValue = next() {
        let gap = nextValue - prev
        // gap が 1 以下なら余白が無いため正規化して再計算する
        if gap <= 1 {
            normalize()
            return sparseOrderValue(previous: previous, next: next, normalize: normalize)
        }
        // gap を二等分した位置を採用することで、両側の順序を壊さずに挿入する
        return prev + gap / 2
    } else if let prev = previous() {
        // 末尾への追加。オーバーフロー時は正規化して再計算する
        let (result, overflow) = prev.addingReportingOverflow(ORDER_SPARSE)
        if overflow {
            normalize()
            return sparseOrderValue(previous: previous, next: next, normalize: normalize)
        }
        return result
    } else if let nextValue = next() {
        // 先頭への追加。アンダーフロー時は正規化して再計算する
        let (result, overflow) = nextValue.subtractingReportingOverflow(ORDER_SPARSE)
        if overflow {
            normalize()
            return sparseOrderValue(previous: previous, next: next, normalize: normalize)
        }
        return result
    } else {
        // 要素が存在しない場合は 0 を基点にする
        return 0
    }
}

/// ドラッグ移動などで連続した範囲に新しい order を割り振る
func assignSparseOrders<T: SparseOrderable>(
    nodes: [T],
    range: ClosedRange<Int>,
    normalize: () -> Void
) {
    guard !nodes.isEmpty else { return }
    let lower = max(range.lowerBound, 0)
    let upper = min(range.upperBound, nodes.count - 1)
    guard lower <= upper else { return }

    let count = upper - lower + 1
    let previousOrder = 0 < lower ? nodes[lower - 1].order : nil
    let nextOrder = upper + 1 < nodes.count ? nodes[upper + 1].order : nil

    if let previous = previousOrder, let next = nextOrder {
        let gap = next - previous
        // gap が count 以下の場合は均等割りできず、正規化を要求する
        if gap <= count {
            normalize()
            return
        }
        // gap を (count + 1) で割ると等間隔の差分が得られる。
        let step = max(1, gap / (count + 1))
        var current = previous
        for offset in 0..<count {
            current += step
            nodes[lower + offset].order = current
        }
    } else if let previous = previousOrder {
        var current = previous
        for index in lower...upper {
            let (next, overflow) = current.addingReportingOverflow(ORDER_SPARSE)
            if overflow {
                normalize()
                return
            }
            current = next
            nodes[index].order = current
        }
    } else if let next = nextOrder {
        var current = next
        for index in stride(from: upper, through: lower, by: -1) {
            let (prev, overflow) = current.subtractingReportingOverflow(ORDER_SPARSE)
            if overflow {
                normalize()
                return
            }
            current = prev
            nodes[index].order = current
        }
    } else {
        var current = 0
        for index in lower...upper {
            nodes[index].order = current
            current += ORDER_SPARSE
        }
    }
}

