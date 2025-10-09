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
    func normalizeGroupOrder() {
        // SwiftData の child 配列は順序が保証されないため、order と id で安定ソートしてから並べ替える
        let sorted = child.sorted { ll, rr in
            if ll.order != rr.order {
                return ll.order < rr.order
            }
            return ll.id < rr.id
        }
        // スパース間隔で再採番しつつ child の順序も更新する
        normalizeSparseOrders(sorted)
        child = sorted
    }

    /// 次のグループの order 値を取得する
    func nextGroupOrder() -> Int {
        let ordered = child.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            // 正規化後に child を最新順序へ入れ替える
            normalizeSparseOrders(ordered)
            child = ordered
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
        element.order = index * ORDER_SPARSE_COUNT
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
        // 末尾への追加。スパース間隔を維持するため固定幅を加算
        return prev + ORDER_SPARSE_COUNT
    } else if let nextValue = next() {
        // 先頭への追加。負方向へ間隔を確保
        return nextValue - ORDER_SPARSE_COUNT
    } else {
        // 要素が存在しない場合は 0 を基点にする
        return 0
    }
}

/// ドラッグ移動などで連続した範囲に新しい order を割り振る
func assignSparseOrders<T: SparseOrderable>(
    items: [T],
    range: ClosedRange<Int>,
    normalize: () -> Void
) {
    guard !items.isEmpty else { return }
    let lower = max(range.lowerBound, 0)
    let upper = min(range.upperBound, items.count - 1)
    guard lower <= upper else { return }

    let count = upper - lower + 1
    let previousOrder = 0 < lower ? items[lower - 1].order : nil
    let nextOrder = upper + 1 < items.count ? items[upper + 1].order : nil

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
            items[lower + offset].order = current
        }
    } else if let previous = previousOrder {
        var current = previous
        for index in lower...upper {
            current += ORDER_SPARSE_COUNT
            items[index].order = current
        }
    } else if let next = nextOrder {
        var current = next
        for index in stride(from: upper, through: lower, by: -1) {
            current -= ORDER_SPARSE_COUNT
            items[index].order = current
        }
    } else {
        var current = 0
        for index in lower...upper {
            items[index].order = current
            current += ORDER_SPARSE_COUNT
        }
    }
}

