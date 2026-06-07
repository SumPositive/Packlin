//  Undo/Redo履歴サービス
//  SwiftDataモデル全体のスナップショット保存と復元をまとめる
//
//  SwiftDataのUndoは不透明・不安定であるため利用せず、自前の履歴レイヤを構築することにした
//  - UndoStackServiceでパック全体のスナップショットを更新前後で保持し、履歴スタックと UI 更新通知を統合管理する
//  - SwiftDataのUndoManagerを差し替えるためUndoStackManagerを用意し、AppMainから履歴サービスを環境へ注入
//  - 最大スタック件数を指定し、Undo/Redoや新規履歴追加のたびにスタック上限を超過した古いレコードを切り捨て履歴の肥大化を抑えるようにした
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class UndoStackService: ObservableObject {
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

    init(maxStackSize: Int = 10) { // 最大スタック件数を指定する
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
            do {
                transactionBefore = try captureSnapshot(context: context)
            } catch {
                // Undo開始時のスナップショット失敗をAnalyticsへ送り、履歴機能の問題分析に使う
                logError(error, domain: "undo_snapshot_begin", message: "スナップショット取得失敗 beginTransaction")
            }
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
            let after: Snapshot
            do {
                after = try captureSnapshot(context: context)
            } catch {
                // Undo確定時のスナップショット失敗をAnalyticsへ送り、履歴機能の問題分析に使う
                logError(error, domain: "undo_snapshot_commit", message: "スナップショット取得失敗 commitTransaction")
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

    /// Undo を 1 回実行する
    /// - 注意: `restore()` 完了後に必ず `persist()` で SQLite へ書き出すこと。
    ///   AppMain では `scenePhase == .background` でしか save しないため、
    ///   Undo 直後にユーザーがアプリを強制終了したり、低メモリで kill されたりすると
    ///   Undo した結果が消えて元に戻った状態が永続化される（ユーザー的には Undo が効かなかったように見える）。
    func undo(context: ModelContext) {
        // 直前の履歴がなければ何もしない（ボタン側で disabled にしているが二重防御）
        guard let record = undoStack.popLast() else {
            updateStates()
            return
        }
        // Redo スタックに移して、再度 Redo できるようにしておく
        redoStack.append(record)
        trimStack(&redoStack)
        // 「before」スナップショットの内容で SwiftData を上書き復元する
        restore(snapshot: record.before, context: context)
        // === ここが Fix 2 で追加した最重要ポイント ===
        // 復元結果を必ず SQLite へ書き出す。これを怠ると Undo 直後の
        // クラッシュ・kill でユーザーの「やり直したい」が永続化されない。
        persist(context: context, domain: "undo_save")
        // 公開プロパティ（canUndo/canRedo）を更新してボタン表示を切り替える
        updateStates()
        // 各画面のヘッダーがボタン活性を再評価できるよう通知を送る
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// Redo を 1 回実行する
    /// - 注意: undo() と同じく、`restore()` 完了後に `persist()` で必ず save する。
    ///   保存しないと Redo 結果がクラッシュ時に失われる。
    func redo(context: ModelContext) {
        // Redo スタックが空なら何もしない
        guard let record = redoStack.popLast() else {
            updateStates()
            return
        }
        // 直前 Undo の逆操作として Undo スタックへ戻す
        undoStack.append(record)
        trimStack(&undoStack)
        // 「after」スナップショット（つまり Undo する前の状態）で復元する
        restore(snapshot: record.after, context: context)
        // === ここが Fix 2 で追加した最重要ポイント ===
        // Undo と同様、Redo 直後にクラッシュしても結果が残るよう即時に永続化する。
        persist(context: context, domain: "redo_save")
        updateStates()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// 重要操作直後に SQLite へ強制的に書き出すヘルパー。
    ///
    /// - 背景:
    ///   SwiftData の `ModelContext` は変更を内部バッファに溜め、明示的な `save()` か
    ///   フレームワークが選んだタイミング（通常はアプリ終了時など）まで永続化しない。
    ///   Packlin では `AppMain.onChange(scenePhase)` で `.background` 遷移時に save しているが、
    ///   これは「ユーザーが直近で操作した内容も含めて、バックグラウンド遷移までは未保存」を意味する。
    ///   通常の編集（テキスト入力など）はバックグラウンド遷移で守られるが、Undo/Redo は
    ///   「一度しか発生しないユーザー意図」なので、失敗するとユーザーの信頼を著しく損なう。
    ///   そのため Undo/Redo 完了の都度 save する。
    ///
    /// - Parameters:
    ///   - context: 永続化対象の `ModelContext`
    ///   - domain: Analytics ログのドメイン名（"undo_save" / "redo_save"）
    private func persist(context: ModelContext, domain: String) {
        // 変更が無ければ save 自体が無駄なのでスキップ。
        // SwiftData の save は I/O を伴うため、無駄な呼び出しを減らす意味でも guard する。
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // save 失敗は致命的だが、ここで例外を伝播しても呼び出し元（UI）で処理できない。
            // Crashlytics/Analytics へ送って傾向分析だけ可能にし、UI の流れは止めない。
            logError(error, domain: domain, message: "context.save 失敗")
        }
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
        let existingPacks: [M1Pack]
        do {
            existingPacks = try context.fetch(FetchDescriptor<M1Pack>())
        } catch {
            // Undo復元時のパック取得失敗をAnalyticsへ送り、復元不能ケースの分析に使う
            logError(error, domain: "undo_restore_fetch", message: "パック取得失敗 restore")
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
