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
//        let sorted = child.sorted { ll, rr in
//            if ll.order != rr.order {
//                return ll.order < rr.order
//            }
//            return ll.id < rr.id
//        }
// 
//        for (index, group) in sorted.enumerated() {
//            group.order = index
//        }
//
//        child = sorted
        
        normalizeSparseOrders(child)
    }

    /// 次のグループの order 値を取得する
    func nextGroupOrder() -> Int {
        let ordered = child.sorted { $0.order < $1.order }
        return sparseOrderForInsertion(items: ordered, index: ordered.count) {
            normalizeSparseOrders(ordered)
        }
    }

    /// パック全体の order を連番に整理する
    static func normalizePackOrder(_ packs: [M1Pack]) {
        let sorted = packs.sorted { $0.order < $1.order }
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

func normalizeSparseOrders<T: SparseOrderable>(_ items: [T]) {
    for (index, element) in items.enumerated() {
        element.order = index * ORDER_SPARSE_COUNT
    }
}

func sparseOrderForInsertion<T: SparseOrderable>(
    items: [T],
    index: Int,
    normalize: () -> Void
) -> Int {
    let clampedIndex = max(0, min(index, items.count))
    return sparseOrderValue(
        previous: { clampedIndex > 0 ? items[clampedIndex - 1].order : nil },
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
        if gap > 1 {
            return prev + gap / 2
        } else {
            normalize()
            return sparseOrderValue(previous: previous, next: next, normalize: normalize)
        }
    } else if let prev = previous() {
        return prev + ORDER_SPARSE_COUNT
    } else if let nextValue = next() {
        return nextValue - ORDER_SPARSE_COUNT
    } else {
        return 0
    }
}

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
    let previousOrder = lower > 0 ? items[lower - 1].order : nil
    let nextOrder = upper + 1 < items.count ? items[upper + 1].order : nil

    if let previous = previousOrder, let next = nextOrder {
        let gap = next - previous
        if gap > count {
            let step = max(1, gap / (count + 1))
            var current = previous
            for offset in 0..<count {
                current += step
                items[lower + offset].order = current
            }
        } else {
            normalize()
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

