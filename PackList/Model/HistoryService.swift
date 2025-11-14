//
//  HistoryService.swift
//  PackList
//
//  Created by sumpo on 2025/11/14.
//
//  SwiftDataのUndoは不透明・不安定であるため利用せず、自前の履歴レイヤを構築することにした
//  - HistoryServiceでパック全体のスナップショットを更新前後で保持し、履歴スタックと UI 更新通知を統合管理する
//  - SwiftDataのUndoManagerを差し替えるためHistoryUndoManagerを用意し、AppMainから履歴サービスを環境へ注入
//  - 最大スタック件数を指定し、Undo/Redoや新規履歴追加のたびにスタック上限を超過した古いレコードを切り捨て履歴の肥大化を抑えるようにした
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class HistoryService: ObservableObject {
    // ユーザー操作前後の状態を完全に保持するためのスナップショット構造体
    struct Snapshot: Equatable {
        struct Pack: Equatable {
            struct Group: Equatable {
                struct Item: Equatable {
                    let id: M3Item.ID
                    let order: Int
                    let name: String
                    let memo: String
                    let check: Bool
                    let stock: Int
                    let need: Int
                    let weight: Int
                }

                let id: M2Group.ID
                let order: Int
                let name: String
                let memo: String
                let items: [Item]
            }

            let id: M1Pack.ID
            let order: Int
            let name: String
            let memo: String
            let createdAt: Date
            let groups: [Group]
        }

        let packs: [Pack]
    }

    private struct Record {
        let before: Snapshot
        let after: Snapshot
    }

    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    /// Undo/Redo の履歴数に上限を設けるための最大件数
    private let maxStackSize: Int
    private var undoStack: [Record] = []
    private var redoStack: [Record] = []

    private var transactionDepth: Int = 0
    private var transactionBefore: Snapshot?
    private var isRestoring: Bool = false

    init(maxStackSize: Int = 100) { // 最大スタック件数を指定する
        // 1件未満だと履歴が成立しないため、必ず1件以上にする
        if maxStackSize < 1 {
            self.maxStackSize = 1
        } else {
            self.maxStackSize = maxStackSize
        }
    }

    func perform(context: ModelContext, operation: () throws -> Void) rethrows {
        // 呼び出し側では begin / end を気にせずに履歴を記録できるようにする
        beginTransaction(context: context)
        defer { commitTransaction(context: context) }
        try operation()
    }

    func beginTransaction(context: ModelContext) {
        // 履歴復元中は新しい履歴を記録しない
        if isRestoring {
            return
        }
        transactionDepth += 1
        if transactionDepth == 1 {
            transactionBefore = try? captureSnapshot(context: context)
        }
    }

    func commitTransaction(context: ModelContext) {
        // 履歴復元中は状態が変わるので、記録処理を抑止する
        if isRestoring {
            return
        }
        if transactionDepth <= 0 {
            transactionDepth = 0
            transactionBefore = nil
            return
        }
        transactionDepth -= 1
        if transactionDepth == 0 {
            guard let before = transactionBefore else {
                transactionBefore = nil
                return
            }
            guard let after = try? captureSnapshot(context: context) else {
                transactionBefore = nil
                return
            }
            transactionBefore = nil
            if before != after {
                undoStack.append(Record(before: before, after: after))
                trimStack(&undoStack)
                redoStack.removeAll()
                updateStates()
                NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            }
        }
    }

    func reset() {
        // バックグラウンド遷移などで履歴を明示的に破棄したいときに利用する
        undoStack.removeAll()
        redoStack.removeAll()
        transactionDepth = 0
        transactionBefore = nil
        updateStates()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    func undo(context: ModelContext) {
        // 直前の履歴がなければ何もしない
        guard let record = undoStack.popLast() else {
            updateStates()
            return
        }
        redoStack.append(record)
        trimStack(&redoStack)
        restore(snapshot: record.before, context: context)
        updateStates()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    func redo(context: ModelContext) {
        guard let record = redoStack.popLast() else {
            updateStates()
            return
        }
        undoStack.append(record)
        trimStack(&undoStack)
        restore(snapshot: record.after, context: context)
        updateStates()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    private func updateStates() {
        // Published プロパティでボタン活性状態を自動更新する
        canUndo = undoStack.isEmpty == false
        canRedo = redoStack.isEmpty == false
    }

    private func captureSnapshot(context: ModelContext) throws -> Snapshot {
        // 順序の不安定さを避けるため、多段のソート条件を設定しておく
        let descriptor = FetchDescriptor<M1Pack>(sortBy: [
            SortDescriptor(\.order, order: .forward),
            SortDescriptor(\.createdAt, order: .forward),
            SortDescriptor(\.id, order: .forward)
        ])
        let packs = try context.fetch(descriptor)
        let snapshotPacks: [Snapshot.Pack] = packs.map { pack in
            let groups = pack.child.sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.id < rhs.id
            }.map { group -> Snapshot.Pack.Group in
                // グループ内のアイテムも order と id で安定ソートする
                let items = group.child.sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }
                    return lhs.id < rhs.id
                }.map { item -> Snapshot.Pack.Group.Item in
                    Snapshot.Pack.Group.Item(
                        id: item.id,
                        order: item.order,
                        name: item.name,
                        memo: item.memo,
                        check: item.check,
                        stock: item.stock,
                        need: item.need,
                        weight: item.weight
                    )
                }
                return Snapshot.Pack.Group(
                    id: group.id,
                    order: group.order,
                    name: group.name,
                    memo: group.memo,
                    items: items
                )
            }
            return Snapshot.Pack(
                id: pack.id,
                order: pack.order,
                name: pack.name,
                memo: pack.memo,
                createdAt: pack.createdAt,
                groups: groups
            )
        }
        return Snapshot(packs: snapshotPacks)
    }

    private func restore(snapshot: Snapshot, context: ModelContext) {
        // 履歴復元中にさらに復元が呼ばれても無視する
        if isRestoring {
            return
        }
        isRestoring = true
        defer {
            transactionDepth = 0
            transactionBefore = nil
            isRestoring = false
        }
        guard let existingPacks = try? context.fetch(FetchDescriptor<M1Pack>()) else {
            return
        }
        var packDictionary: [M1Pack.ID: M1Pack] = Dictionary(uniqueKeysWithValues: existingPacks.map { ($0.id, $0) })
        var packOrder: [M1Pack] = []
        for packSnapshot in snapshot.packs {
            // 既存のパックがあれば更新し、無ければ新規作成する
            let pack: M1Pack
            if let existing = packDictionary.removeValue(forKey: packSnapshot.id) {
                pack = existing
            } else {
                pack = M1Pack(id: packSnapshot.id,
                              name: packSnapshot.name,
                              memo: packSnapshot.memo,
                              createdAt: packSnapshot.createdAt,
                              order: packSnapshot.order)
                context.insert(pack)
            }
            pack.name = packSnapshot.name
            pack.memo = packSnapshot.memo
            pack.createdAt = packSnapshot.createdAt
            pack.order = packSnapshot.order
            updateGroups(of: pack, with: packSnapshot.groups, context: context)
            packOrder.append(pack)
        }
        // 履歴に含まれないパックは削除する
        for (_, removed) in packDictionary {
            context.delete(removed)
        }
        for pack in packOrder {
            reorderChildren(of: pack)
        }
    }

    private func updateGroups(of pack: M1Pack, with groups: [Snapshot.Pack.Group], context: ModelContext) {
        // グループも同様に ID ごとに差分適用する
        var groupDictionary: [M2Group.ID: M2Group] = Dictionary(uniqueKeysWithValues: pack.child.map { ($0.id, $0) })
        var orderedGroups: [M2Group] = []
        for groupSnapshot in groups {
            let group: M2Group
            if let existing = groupDictionary.removeValue(forKey: groupSnapshot.id) {
                group = existing
            } else {
                group = M2Group(id: groupSnapshot.id,
                                name: groupSnapshot.name,
                                memo: groupSnapshot.memo,
                                order: groupSnapshot.order,
                                parent: pack)
                context.insert(group)
            }
            group.parent = pack
            group.name = groupSnapshot.name
            group.memo = groupSnapshot.memo
            group.order = groupSnapshot.order
            updateItems(of: group, with: groupSnapshot.items, context: context)
            orderedGroups.append(group)
        }
        // 残ったグループは履歴上存在しないので削除する
        for (_, removed) in groupDictionary {
            context.delete(removed)
        }
        pack.child = orderedGroups
    }

    private func updateItems(of group: M2Group, with items: [Snapshot.Pack.Group.Item], context: ModelContext) {
        // アイテムを1件ずつ復元し、余剰分は削除する
        var itemDictionary: [M3Item.ID: M3Item] = Dictionary(uniqueKeysWithValues: group.child.map { ($0.id, $0) })
        var orderedItems: [M3Item] = []
        for itemSnapshot in items {
            let item: M3Item
            if let existing = itemDictionary.removeValue(forKey: itemSnapshot.id) {
                item = existing
            } else {
                item = M3Item(id: itemSnapshot.id,
                              name: itemSnapshot.name,
                              memo: itemSnapshot.memo,
                              check: itemSnapshot.check,
                              stock: itemSnapshot.stock,
                              need: itemSnapshot.need,
                              weight: itemSnapshot.weight,
                              order: itemSnapshot.order,
                              parent: group)
                context.insert(item)
            }
            item.parent = group
            item.name = itemSnapshot.name
            item.memo = itemSnapshot.memo
            item.check = itemSnapshot.check
            item.stock = itemSnapshot.stock
            item.need = itemSnapshot.need
            item.weight = itemSnapshot.weight
            item.order = itemSnapshot.order
            orderedItems.append(item)
        }
        for (_, removed) in itemDictionary {
            context.delete(removed)
        }
        group.child = orderedItems
    }

    private func reorderChildren(of pack: M1Pack) {
        // SwiftData の child 配列は順序未定義なので、履歴に沿って並び替える
        let orderedGroups = pack.child.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }
        pack.child = orderedGroups
    }

    private func trimStack(_ stack: inout [Record]) {
        // 最大件数を超えたときは古い履歴から順に削除してメモリ使用量を抑える
        if maxStackSize < stack.count {
            let overflow = stack.count - maxStackSize
            if overflow < stack.count {
                stack.removeFirst(overflow)
            } else {
                stack.removeAll()
            }
        }
    }
}
