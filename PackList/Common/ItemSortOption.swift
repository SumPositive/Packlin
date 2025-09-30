//
//  ItemSortOption.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI

enum ItemSortOption: String, CaseIterable, Identifiable, Codable {
    case unchecked
    case lackCount
    case lackWeight
    case stockWeight

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .lackCount:
            return "item.sort.title.lackCount" //"不足個数順"
        case .lackWeight:
            return "item.sort.title.lackWeight" //"不足重量順"
        case .stockWeight:
            return "item.sort.title.stockWeight" //"在庫重量順"
        case .unchecked:
            return "item.sort.title.unchecked" //"未チェック順"
        }
    }

    func sortedItems(from pack: M1Pack) -> [M3Item] {
        let groups = pack.child.sorted { $0.order < $1.order }
        let items = groups.flatMap { group in
            group.child.sorted { $0.order < $1.order }
        }

        switch self {
        case .lackCount:
            return items.sorted(by: { lhs, rhs in
                compare(lhs: lhs, rhs: rhs, primary: lhs.need - lhs.stock, rhsPrimary: rhs.need - rhs.stock)
            })
        case .lackWeight:
            return items.sorted(by: { lhs, rhs in
                let lhsValue = (lhs.need - lhs.stock) * lhs.weight
                let rhsValue = (rhs.need - rhs.stock) * rhs.weight
                return compare(lhs: lhs, rhs: rhs, primary: lhsValue, rhsPrimary: rhsValue)
            })
        case .stockWeight:
            return items.sorted(by: { lhs, rhs in
                let lhsValue = lhs.stock * lhs.weight
                let rhsValue = rhs.stock * rhs.weight
                return compare(lhs: lhs, rhs: rhs, primary: lhsValue, rhsPrimary: rhsValue)
            })
        case .unchecked:
            return items.sorted(by: { lhs, rhs in
                let lhsValue = uncheckedKey(for: lhs)
                let rhsValue = uncheckedKey(for: rhs)
                if lhsValue != rhsValue {
                    return lhsValue < rhsValue
                }
                return fallbackCompare(lhs: lhs, rhs: rhs)
            })
        }
    }

    private func compare(lhs: M3Item, rhs: M3Item, primary: Int, rhsPrimary: Int) -> Bool {
        if primary != rhsPrimary {
            return primary > rhsPrimary
        }
        return fallbackCompare(lhs: lhs, rhs: rhs)
    }

    private func fallbackCompare(lhs: M3Item, rhs: M3Item) -> Bool {
        let lhsGroupOrder = lhs.parent?.order ?? Int.max
        let rhsGroupOrder = rhs.parent?.order ?? Int.max
        if lhsGroupOrder != rhsGroupOrder {
            return lhsGroupOrder < rhsGroupOrder
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.id < rhs.id
    }

    /// 未チェック sort key
    private func uncheckedKey(for item: M3Item) -> Int {
        if item.check {
            if item.need == 0 {
                return 4 // チェック＆不要
            }
            else if item.stock < item.need {
                return 2 // チェック＆不足
            }
            return 3 // チェック
        }else{
            if item.need == 0 {
                return 5 // 未チェック＆不要
            }
            else if item.stock < item.need {
                return 0 // 未チェック＆不足
            }
            return 1 // 未チェック＆充足
        }
    }
}
