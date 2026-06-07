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

    /// トランザクション（編集の塊）の開始
    ///
    /// 設計の不変条件（Fix 10 で明示化）:
    ///   1. `transactionDepth` は常に `>= 0`
    ///   2. `transactionBefore` は「深度 0 になったときの diff 比較元」として使う
    ///      → 復元（restore）が走ると無効化して nil になる
    ///   3. ネストした begin/end はカウンタで束ねられ、最も外側の begin/end ペアだけが
    ///      実際の履歴記録を行う
    ///
    /// 動作:
    ///   - depth 0 → 1: スナップショットを取得して transactionBefore に保存
    ///   - depth >= 1 でさらに begin: 深度を上げるだけ（ネスト処理）
    func beginTransaction(context: ModelContext) {
        // 履歴復元中（restore 実行中）は新しい履歴を記録しないため、何もしない
        if isRestoring {
            return
        }
        transactionDepth += 1
        // 最外周の begin だけスナップショットを取得する
        if transactionDepth == 1 {
            do {
                transactionBefore = try captureSnapshot(context: context)
            } catch {
                // スナップショット失敗時は transactionBefore を nil のままにする。
                // この後の commit では「snapshot=nil なので無視」になり、安全に no-op となる。
                transactionBefore = nil
                logError(error, domain: "undo_snapshot_begin", message: "スナップショット取得失敗 beginTransaction")
            }
        }
    }

    /// トランザクション（編集の塊）の終了
    ///
    /// === Fix 10: transactionDepth リセットの安全化 ===
    ///
    /// 旧版の問題点:
    ///   - `restore()` が `transactionDepth = 0` で強制リセットしていた
    ///   - 復元前に開いていた編集 View の `groupingEnd` が後から呼ばれると
    ///     depth が負方向に進み、`if transactionDepth <= 0` ガードで救われていた
    ///   - 救われる設計ではあるがコメントが薄く、コードを読んだだけでは
    ///     なぜそうなっているか理解できず脆い
    ///
    /// 新版の改善:
    ///   1. **Saturating decrement**: depth が 0 のときは減算せず早期 return
    ///      → depth が決して負にならない（不変条件 #1 を厳守）
    ///   2. **`transactionBefore` の nil チェックを最初に**: restore() で nil 化された
    ///      transactionBefore は「無効化された」マーカーとして扱う
    ///   3. **冗長な状態リセット**: 失敗パスでも必ず transactionBefore = nil で
    ///      クリーンな状態に戻す（次の begin/end が安全に動くよう保証）
    ///
    /// 起こりうるシナリオと対応:
    ///   (a) 正常: begin → end → 履歴記録 ✓
    ///   (b) ネスト: begin → begin → end → end → 履歴記録は最外端で1回だけ ✓
    ///   (c) restore 後の遅延 end:
    ///       begin → restore（depth=0, before=nil） → end（depth>0 から depth>=0 に減算→ commit試行 → before=nil で no-op） ✓
    ///       ※ restore で depth=0 に強制リセットされるため、遅延 end は早期 return される
    ///   (d) スナップショット失敗: transactionBefore=nil で安全に no-op ✓
    func commitTransaction(context: ModelContext) {
        // 履歴復元中（restore 実行中）は記録しない
        if isRestoring {
            return
        }

        // === 安全ガード 1: depth が 0 のとき（スタブな end 呼び出し） ===
        // 原因の候補:
        //   - View の onDisappear が onAppear なしで呼ばれた（Fix 7 で個別 View には対策済みだが、
        //     念のためサービス側でも防御）
        //   - restore() が depth を 0 にリセットした後に、過去の begin に対応する end が遅延到着した
        //   - 開発者ミスで groupingEnd を groupingBegin より先に呼んだ
        // どのケースでも depth を負にせず、状態をクリーンにして安全に return する。
        guard transactionDepth > 0 else {
            transactionDepth = 0
            transactionBefore = nil
            return
        }

        // ネストの深度を 1 つ下げる
        transactionDepth -= 1

        // 最外周の end でなければここで終了（ネスト中はまだ確定しない）
        if transactionDepth != 0 {
            return
        }

        // === 以下、最外周の end の処理 ===
        // 必ず transactionBefore を nil 化してからの早期 return を許すよう、
        // 一旦ローカルに退避してから処理する。これにより以降の begin/end が安全に動く。
        let before = transactionBefore
        transactionBefore = nil

        // === 安全ガード 2: スナップショットの有効性チェック ===
        // before が nil になる典型ケース:
        //   - beginTransaction でのスナップショット取得が失敗していた
        //   - 開始から終了までの間に restore() が走り、transactionBefore を無効化した
        // どちらも「このトランザクションを履歴に記録すべきでない」状態なので、no-op で終了。
        guard let before else { return }

        // 終了時点のスナップショットを取得
        let after: Snapshot
        do {
            after = try captureSnapshot(context: context)
        } catch {
            // 取得失敗 = 比較できない = 履歴に記録できない。
            // before は既に nil 化済みなので追加クリーンアップは不要。
            logError(error, domain: "undo_snapshot_commit", message: "スナップショット取得失敗 commitTransaction")
            return
        }

        // 状態が変化していれば履歴に記録（同じなら無意味な履歴を増やさない）
        if before != after {
            undoStack.append(Record(before: before, after: after))
            trimStack(&undoStack)
            // 新規操作が入ったので、これまでの redo 履歴は無効化する
            redoStack.removeAll()
            updateStates()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
    }

    /// 履歴と進行中トランザクションをすべて破棄する
    ///
    /// 用途:
    ///   - サンプルパック読み込み完了時のリセット
    ///   - バックグラウンド遷移時に「もう Undo は無し」にしたい場合
    ///   - 開発時のデバッグリセット
    ///
    /// === Fix 10: restore() と同じく状態を完全クリーンにする ===
    /// transactionDepth と transactionBefore をリセットすることで、reset() 後に
    /// 古い begin の残骸が end として遅延到着しても、commitTransaction の安全ガードで
    /// 無害化される（負の depth カウントや古いスナップショットでの誤記録を防ぐ）。
    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        // restore() と同じ状態リセットを適用（一貫性のため）
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

    /// スナップショットの内容で SwiftData を上書き復元する
    ///
    /// === Fix 8: Group / Item の Pack 越境（クロス階層移動）対応 ===
    ///
    /// 旧版は「Pack ごとに `pack.child` を見て差分適用」していたため、
    /// 以下のシナリオで動作が壊れていた：
    ///   1. Group G が Pack A に属していた
    ///   2. ユーザーが G を Pack B へ移動
    ///   3. ユーザーが Undo を押す
    ///   4. 旧 restore は「Pack A の child」を見るが、G はもう Pack B にいる
    ///   5. groupDictionary に G が無いため else 分岐で **新規 M2Group(id: G.id, ...)** を作る
    ///   6. しかし DB には既に同じ id の M2Group が存在（Pack B 配下）
    ///   7. `@Attribute(.unique) var id` の制約違反で save 時にエラー、データ不整合
    ///
    /// 新版は **全 Group / 全 Item を最初にグローバル辞書化** してから、
    /// スナップショットの所属に従って re-parent する：
    ///   - Group G を id 検索すれば、現在の所属 Pack に関係なく見つけられる
    ///   - `group.parent = snapshotPack` で正しい Pack に付け替える
    ///   - SwiftData の inverse リレーションシップにより、旧 Pack の child から
    ///     自動的に外れる
    ///
    /// これにより以下のシナリオが正しく動く：
    ///   - Group の Pack 越境（A → B → Undo で A に戻る）
    ///   - Item の Group 越境（同一 Pack 内）
    ///   - Item の Group 越境（Pack を跨ぐ移動）
    ///   - 複数項目のドラッグ移動の Undo
    private func restore(snapshot: Snapshot, context: ModelContext) {
        // 履歴復元中にさらに復元が呼ばれても無視する（再入防止）
        if isRestoring {
            return
        }
        isRestoring = true
        defer {
            // === Fix 10: 復元完了後の状態リセット（安全化版） ===
            //
            // 復元完了時に状態を強制的にリセットする理由：
            //   - 復元前に開いていた transactionBefore は古いスナップショット（restore 前の状態）を
            //     参照しているため、そのまま commit されると「不正な diff」が履歴に記録される
            //   - restore 中・後に発生する begin/end は新しい transaction として再カウントする必要がある
            //
            // リセット内容と理由：
            //   - transactionDepth = 0: 復元前に開いていた View の groupingEnd が後から呼ばれても、
            //     commitTransaction の安全ガード 1（depth <= 0 で早期 return）で吸収される
            //   - transactionBefore = nil: 古いスナップショットを参照しないよう明示的にクリア
            //   - isRestoring = false: 復元処理の終了を明示
            //
            // 順序の意図（上から下へ）：
            //   1. depth と before を先にリセット（commit が誤動作しない状態にする）
            //   2. 最後に isRestoring を false にする（beginTransaction の早期 return が解除される）
            //
            // この順序により、isRestoring=false になった瞬間に走るかもしれない beginTransaction は
            // クリーンな状態（depth=0, before=nil）から開始できる。
            transactionDepth = 0
            transactionBefore = nil
            isRestoring = false
        }

        // === Step 1: 全 Pack / Group / Item をフェッチして辞書化 ===
        // Fix 8: Pack 単位ではなく **DB 全体** から id 検索できるよう、
        // 全 Group と全 Item を一括でフェッチして辞書化する。
        // これにより Pack 越境した Group / Item も正しく再配置できる。
        let existingPacks: [M1Pack]
        let existingGroups: [M2Group]
        let existingItems: [M3Item]
        do {
            existingPacks = try context.fetch(FetchDescriptor<M1Pack>())
            existingGroups = try context.fetch(FetchDescriptor<M2Group>())
            existingItems = try context.fetch(FetchDescriptor<M3Item>())
        } catch {
            // フェッチ失敗は致命的だが、UI 側で復元できないので Analytics 送信のみ。
            logError(error, domain: "undo_restore_fetch", message: "Pack/Group/Item 取得失敗 restore")
            return
        }

        // id → エンティティの辞書。`removeValue(forKey:)` で「採用済み」を消費し、
        // ループ終了後に残ったものは「スナップショットに無い → 削除対象」と判定する。
        var packDictionary: [M1Pack.ID: M1Pack] = Dictionary(uniqueKeysWithValues: existingPacks.map { ($0.id, $0) })
        // === Fix 8: グローバル辞書を追加 ===
        // Pack 単位ではなく全 Group / 全 Item を 1 つの辞書で管理することで、
        // Pack を跨いだ移動の Undo / Redo が正しく動く。
        var globalGroupDictionary: [M2Group.ID: M2Group] = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.id, $0) })
        var globalItemDictionary: [M3Item.ID: M3Item] = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })

        // === Step 2: スナップショットの順序で Pack を復元 ===
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
            // === Fix 8: グローバル辞書を渡して updateGroups を呼ぶ ===
            updateGroups(
                of: pack,
                with: packSnapshot.groups,
                globalGroupDictionary: &globalGroupDictionary,
                globalItemDictionary: &globalItemDictionary,
                context: context
            )
            packOrder.append(pack)
        }

        // === Step 3: スナップショットに無い Pack / Group / Item をすべて削除 ===
        // - Pack: 履歴上存在しないので削除（cascade で配下の Group / Item も削除される）
        // - Group: どの Pack のスナップショットにも含まれていなかったもの（孤児）
        // - Item: どの Group のスナップショットにも含まれていなかったもの（孤児）
        //
        // Pack cascade で多くの Group / Item は既に削除されているが、グローバル辞書に
        // 残ったままになるので、ここで明示的に delete を呼んでも害はない
        // （既に削除済みオブジェクトへの delete は SwiftData が no-op として扱う）。
        for (_, removed) in packDictionary {
            context.delete(removed)
        }
        for (_, removed) in globalGroupDictionary {
            context.delete(removed)
        }
        for (_, removed) in globalItemDictionary {
            context.delete(removed)
        }

        // === Step 4: 各 Pack の child の表示順をスナップショット通りに揃える ===
        for pack in packOrder {
            reorderChildren(of: pack)
        }
    }

    /// 1 つの Pack 配下の Group をスナップショットの内容で復元する
    ///
    /// === Fix 8: グローバル辞書ベースに変更 ===
    /// 旧版は `pack.child` から groupDictionary を作っていたため、Pack 越境した
    /// Group を見つけられなかった。新版は呼び出し元から渡される
    /// `globalGroupDictionary`（DB 全体の Group を id でインデックス化したもの）
    /// から検索することで、現在どの Pack に属していようと再配置できる。
    private func updateGroups(
        of pack: M1Pack,
        with groups: [Snapshot.Pack.Group],
        globalGroupDictionary: inout [M2Group.ID: M2Group],
        globalItemDictionary: inout [M3Item.ID: M3Item],
        context: ModelContext
    ) {
        var orderedGroups: [M2Group] = []
        for groupSnapshot in groups {
            let group: M2Group
            // === Fix 8: グローバル辞書から検索 ===
            // 現在どの Pack の子になっていても、id で見つけられる。
            if let existing = globalGroupDictionary.removeValue(forKey: groupSnapshot.id) {
                group = existing
            } else {
                // グローバル辞書にもない → 完全な新規 Group
                group = M2Group(id: groupSnapshot.id,
                                name: groupSnapshot.name,
                                memo: groupSnapshot.memo,
                                order: groupSnapshot.order,
                                parent: pack)
                context.insert(group)
            }
            // === Fix 8: re-parent ===
            // 既存の Group を別 Pack から「持ってきた」場合、ここで親を付け替える。
            // SwiftData の inverse リレーションシップ（`@Relationship(inverse: \M1Pack.child)`）
            // により、旧 Pack の `child` 配列からは自動的に外れる。
            group.parent = pack
            group.name = groupSnapshot.name
            group.memo = groupSnapshot.memo
            group.order = groupSnapshot.order
            // === Fix 8: 配下の Item もグローバル辞書経由で更新 ===
            updateItems(
                of: group,
                with: groupSnapshot.items,
                globalItemDictionary: &globalItemDictionary,
                context: context
            )
            orderedGroups.append(group)
        }
        // pack.child を明示的に上書きして、スナップショット通りの並び順にする。
        // re-parent で外れた Group はここに含まれないため、自動的に他 Pack に
        // 移っているか、後段の削除フェーズで処理される。
        pack.child = orderedGroups
    }

    /// 1 つの Group 配下の Item をスナップショットの内容で復元する
    ///
    /// === Fix 8: グローバル辞書ベースに変更 ===
    /// updateGroups と同じ理由で、グローバル Item 辞書から id 検索する。
    /// これにより Item が Group 間（同一 Pack でも別 Pack でも）を移動した履歴の
    /// Undo / Redo が正しく動く。
    private func updateItems(
        of group: M2Group,
        with items: [Snapshot.Pack.Group.Item],
        globalItemDictionary: inout [M3Item.ID: M3Item],
        context: ModelContext
    ) {
        var orderedItems: [M3Item] = []
        for itemSnapshot in items {
            let item: M3Item
            // === Fix 8: グローバル辞書から検索 ===
            if let existing = globalItemDictionary.removeValue(forKey: itemSnapshot.id) {
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
            // === Fix 8: re-parent ===
            // 別 Group から持ってきた Item は親を付け替える。
            // inverse リレーションシップにより旧 Group の child からは自動で外れる。
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
        // group.child を明示的に上書きして、スナップショット通りの並び順にする。
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
