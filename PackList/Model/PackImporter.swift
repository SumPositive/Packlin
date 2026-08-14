//
//  PackImporter.swift
//  PackList
//
//  Created by sumpo on 2025/09/23.
//
//  ──────────────────────────────────────────────────────────────────────────
//  外部 JSON（単体パック .packlin / バックアップ .packlinbackup）を SwiftData の
//  M1Pack / M2Group / M3Item に取り込むサービス。
//
//  === Fix 5: ImportDTO バリデーション ===
//  入力 JSON は信頼できないため（破損ファイル・他端末で改竄された JSON・
//  AI が生成したフォーマット違反データ等の可能性）、取り込み時に必ず
//  サニタイズしてから DB へ流し込む。
//
//  サニタイズ対象:
//    - 文字列長：name / memo は APP_MAX_NAME_LEN / APP_MAX_MEMO_LEN に切り詰め
//    - 数値範囲：weight / stock / need は 0…MAX のクランプ
//    - 件数：groups は APP_MAX_PART_ROWS、items は APP_MAX_ITEM_ROWS で切り捨て
//
//  サニタイズしないと以下のような事故が起こり得る：
//    - 数十万文字の name で UI レンダリングがフリーズ
//    - 負数の need で重量集計が暴走（lack = need - stock が巨大負数）
//    - Int.max に近い weight で overflow → 集計クラッシュ
//    - 数千件のグループで List スクロールが極端に重くなる
//
//  なお、レガシー V2 → V3 マイグレーション（MigratingFromV2toV3）は数値だけ
//  max(value, 0) で防御していたが、文字列長や件数は未対応だった。
//  本ファイルのサニタイズはマイグレーションよりも厳格で、両方の入口を覆える。
//

import Foundation
import SwiftData

/// AI差分の検証または適用に失敗した場合
enum PackChangeApplicationError: Error {
    case invalidChanges
}

struct PackImporter {

    // MARK: - Public API

    /// 新規にパックを取り込む（同名/同 ID パックが既存に無い場合）
    /// - すべての入力は `SanitizedDTO` 経由でクランプされる
    /// - 件数が APP_MAX_PART_ROWS / APP_MAX_ITEM_ROWS を超える場合は先頭から切り捨て
    @discardableResult
    static func insertPack(from dto: PackJsonDTO, into context: ModelContext, order: Int) -> M1Pack {
        // === 文字列・数値・件数を一括サニタイズ ===
        // ここで安全な値に正規化することで、以降の処理は信頼された前提で書ける
        let sanitized = SanitizedDTO(from: dto)

        let pack = M1Pack(
            name: sanitized.name,
            memo: sanitized.memo,
            createdAt: sanitized.createdAt,
            order: order
        )
        context.insert(pack)

        // sanitized.groups は既に order/index で安定ソート＆件数クランプ済み
        for (groupIndex, sanitizedGroup) in sanitized.groups.enumerated() {
            let group = M2Group(
                name: sanitizedGroup.name,
                memo: sanitizedGroup.memo,
                order: groupIndex * ORDER_SPARSE,
                parent: pack
            )
            context.insert(group)
            pack.child.append(group)

            for (itemIndex, sanitizedItem) in sanitizedGroup.items.enumerated() {
                let item = M3Item(
                    name: sanitizedItem.name,
                    memo: sanitizedItem.memo,
                    check: sanitizedItem.check,
                    // 新フォーマットでは在庫は常にアプリ側で初期化（取り込み直後は 0 が自然）
                    stock: sanitizedItem.stock,
                    need: sanitizedItem.need,
                    weight: sanitizedItem.weight,
                    order: itemIndex * ORDER_SPARSE,
                    parent: group
                )
                context.insert(item)
                group.child.append(item)
            }
        }

        return pack
    }

    /// 既存パックを取り込み内容で上書きする（バックアップ復元・名称一致の単体パック取り込み）
    /// - サニタイズは insertPack と同じく `SanitizedDTO` 経由
    /// - パックの `id` と現在の `order` は元の値を保持する
    @discardableResult
    static func overwrite(pack: M1Pack, with dto: PackJsonDTO, in context: ModelContext) -> M1Pack {
        // === 文字列・数値・件数を一括サニタイズ ===
        let sanitized = SanitizedDTO(from: dto)

        // === 既存パックの属性を上書き ===
        // id と order は元のものを保持する（外部からは見えない内部識別子と、
        // 一覧での並び位置を変えないため）
        pack.name = sanitized.name
        pack.memo = sanitized.memo
        pack.createdAt = sanitized.createdAt

        // === 旧データを掃除する ===
        // 上書き取り込みでは既存のグループ・アイテムを全て消してから DTO を流し込む。
        // これは「旧データの一部が新データと混ざる」状態を防ぐため。
        //
        // === Fix 3: SwiftData リレーションシップの安全なイテレーション ===
        // `pack.child` は SwiftData の `@Relationship` で動的に管理される配列で、
        // `context.delete(group)` を呼ぶとフレームワーク側で `pack.child` の
        // 内部キャッシュも更新される。
        //
        // Swift の `for in` は通常コピーセマンティクスだが、`@Relationship` の
        // backing storage はビューのような実装になっており、イテレーション中の
        // 外部変更で挙動が壊れる可能性がある（実機で再現性は低いが、SwiftData の
        // 内部実装に依存する未定義動作）。
        //
        // そのため反復対象を `Array(...)` で明示コピーしてから for-in する。
        // これでイテレーション対象は値型の通常配列となり、SwiftData 側の変更から
        // 切り離される。
        let existingGroups = Array(pack.child)
        for group in existingGroups {
            // M2Group の @Relationship(deleteRule: .cascade) により、
            // group 配下の Item も連鎖的に削除される。
            context.delete(group)
        }
        // 安全策として pack.child を明示的に空配列で初期化する。
        // cascade 削除が完了していれば既に空のはずだが、内部状態が
        // 同期前の場合に備えて確実にクリアしておく。
        pack.child = []

        // sanitized.groups は既に order/index で安定ソート＆件数クランプ済み
        for (groupIndex, sanitizedGroup) in sanitized.groups.enumerated() {
            let group = M2Group(
                name: sanitizedGroup.name,
                memo: sanitizedGroup.memo,
                order: groupIndex * ORDER_SPARSE,
                parent: pack
            )
            context.insert(group)
            pack.child.append(group)

            for (itemIndex, sanitizedItem) in sanitizedGroup.items.enumerated() {
                let item = M3Item(
                    name: sanitizedItem.name,
                    memo: sanitizedItem.memo,
                    check: sanitizedItem.check,
                    stock: sanitizedItem.stock,
                    need: sanitizedItem.need,
                    weight: sanitizedItem.weight,
                    order: itemIndex * ORDER_SPARSE,
                    parent: group
                )
                context.insert(item)
                group.child.append(item)
            }
        }

        return pack
    }

    /// AIが返した差分だけを現在パックへ順番に適用する
    @discardableResult
    static func applyChanges(_ changes: [PackChangeDTO],
                             to currentPack: M1Pack?,
                             in context: ModelContext,
                             newPackOrder: Int) throws -> M1Pack {
        // 変更前に全参照を検証し、途中まで反映された状態を作らない
        guard validateChanges(changes, currentPack: currentPack) else {
            throw PackChangeApplicationError.invalidChanges
        }

        var pack = currentPack
        var referencedGroups: [String: M2Group] = [:]
        var referencedItems: [String: M3Item] = [:]

        for change in changes {
            switch change.action {
            case .createPack:
                let createdPack = M1Pack(
                    name: sanitizedName(change.name ?? ""),
                    memo: sanitizedMemo(change.memo ?? ""),
                    createdAt: Date(),
                    order: newPackOrder
                )
                context.insert(createdPack)
                pack = createdPack
            case .updatePack:
                guard let pack else { throw PackChangeApplicationError.invalidChanges }
                if let name = change.name { pack.name = sanitizedName(name) }
                if let memo = change.memo { pack.memo = sanitizedMemo(memo) }
            case .addGroup:
                guard let pack, let referenceId = change.referenceId else {
                    throw PackChangeApplicationError.invalidChanges
                }
                let group = M2Group(
                    name: sanitizedName(change.name ?? ""),
                    memo: sanitizedMemo(change.memo ?? ""),
                    parent: pack
                )
                context.insert(group)
                pack.child.append(group)
                referencedGroups[referenceId] = group
                reorderGroup(group, in: pack, placement: change.placement, afterId: change.afterId,
                             referencedGroups: referencedGroups)
            case .updateGroup:
                guard let pack,
                      let group = resolveGroup(change.targetId, in: pack, references: referencedGroups) else {
                    throw PackChangeApplicationError.invalidChanges
                }
                if let name = change.name { group.name = sanitizedName(name) }
                if let memo = change.memo { group.memo = sanitizedMemo(memo) }
            case .deleteGroup:
                guard let pack,
                      let group = resolveGroup(change.targetId, in: pack, references: referencedGroups) else {
                    throw PackChangeApplicationError.invalidChanges
                }
                pack.child.removeAll { $0.id == group.id }
                context.delete(group)
                normalizeSparseOrders(pack.child.sorted { $0.order < $1.order })
            case .moveGroup:
                guard let pack,
                      let group = resolveGroup(change.targetId, in: pack, references: referencedGroups) else {
                    throw PackChangeApplicationError.invalidChanges
                }
                reorderGroup(group, in: pack, placement: change.placement, afterId: change.afterId,
                             referencedGroups: referencedGroups)
            case .addItem:
                guard let pack,
                      let referenceId = change.referenceId,
                      let group = resolveGroup(change.parentId, in: pack, references: referencedGroups) else {
                    throw PackChangeApplicationError.invalidChanges
                }
                let item = M3Item(
                    name: sanitizedName(change.name ?? ""),
                    memo: sanitizedMemo(change.memo ?? ""),
                    check: change.check ?? false,
                    stock: clamped(change.stock ?? 0, upperBound: APP_MAX_STOCK_NUM),
                    need: clamped(change.need ?? 1, upperBound: APP_MAX_NEED_NUM),
                    weight: clamped(change.weight ?? 0, upperBound: APP_MAX_WEIGHT_NUM),
                    parent: group
                )
                context.insert(item)
                group.child.append(item)
                referencedItems[referenceId] = item
                reorderItem(item, in: group, placement: change.placement, afterId: change.afterId,
                            referencedItems: referencedItems)
            case .updateItem:
                guard let pack,
                      let item = resolveItem(change.targetId, in: pack, references: referencedItems) else {
                    throw PackChangeApplicationError.invalidChanges
                }
                if let name = change.name { item.name = sanitizedName(name) }
                if let memo = change.memo { item.memo = sanitizedMemo(memo) }
                if let check = change.check { item.check = check }
                if let stock = change.stock { item.stock = clamped(stock, upperBound: APP_MAX_STOCK_NUM) }
                if let need = change.need { item.need = clamped(need, upperBound: APP_MAX_NEED_NUM) }
                if let weight = change.weight { item.weight = clamped(weight, upperBound: APP_MAX_WEIGHT_NUM) }
            case .deleteItem:
                guard let pack,
                      let item = resolveItem(change.targetId, in: pack, references: referencedItems),
                      let group = item.parent else {
                    throw PackChangeApplicationError.invalidChanges
                }
                group.child.removeAll { $0.id == item.id }
                context.delete(item)
                normalizeSparseOrders(group.child.sorted { $0.order < $1.order })
            case .moveItem:
                guard let pack,
                      let item = resolveItem(change.targetId, in: pack, references: referencedItems),
                      let sourceGroup = item.parent,
                      let targetGroup = resolveGroup(change.parentId, in: pack, references: referencedGroups) else {
                    throw PackChangeApplicationError.invalidChanges
                }
                if sourceGroup.id != targetGroup.id {
                    sourceGroup.child.removeAll { $0.id == item.id }
                    item.parent = targetGroup
                    targetGroup.child.append(item)
                    normalizeSparseOrders(sourceGroup.child.sorted { $0.order < $1.order })
                }
                reorderItem(item, in: targetGroup, placement: change.placement, afterId: change.afterId,
                            referencedItems: referencedItems)
            }
        }

        guard let pack else { throw PackChangeApplicationError.invalidChanges }
        return pack
    }
}

private extension PackImporter {
    /// 差分内のID参照と件数上限を適用前に確認する
    static func validateChanges(_ changes: [PackChangeDTO], currentPack: M1Pack?) -> Bool {
        guard changes.isEmpty == false, changes.count <= 100 else { return false }
        var hasPack = currentPack != nil
        var groupIds = Set(currentPack?.child.map(\.id) ?? [])
        var itemParents: [String: String] = [:]
        var itemCounts: [String: Int] = [:]
        var referenceIds = Set<String>()

        for group in currentPack?.child ?? [] {
            itemCounts[group.id] = group.child.count
            for item in group.child {
                guard itemParents[item.id] == nil else { return false }
                itemParents[item.id] = group.id
            }
        }

        for (index, change) in changes.enumerated() {
            switch change.action {
            case .createPack:
                guard hasPack == false, index == 0, hasUsableName(change.name) else { return false }
                hasPack = true
            case .updatePack:
                guard hasPack, change.name != nil || change.memo != nil else { return false }
                if change.name != nil, hasUsableName(change.name) == false { return false }
            case .addGroup:
                guard hasPack, groupIds.count < APP_MAX_PART_ROWS,
                      let referenceId = change.referenceId,
                      referenceIds.contains(referenceId) == false,
                      groupIds.contains(referenceId) == false,
                      itemParents[referenceId] == nil,
                      hasUsableName(change.name),
                      validPlacement(change, availableIds: groupIds) else { return false }
                referenceIds.insert(referenceId)
                groupIds.insert(referenceId)
                itemCounts[referenceId] = 0
            case .updateGroup:
                guard let targetId = change.targetId, groupIds.contains(targetId),
                      change.name != nil || change.memo != nil else { return false }
                if change.name != nil, hasUsableName(change.name) == false { return false }
            case .deleteGroup:
                guard let targetId = change.targetId, groupIds.remove(targetId) != nil else { return false }
                itemCounts[targetId] = nil
                itemParents = itemParents.filter { $0.value != targetId }
            case .moveGroup:
                guard let targetId = change.targetId, groupIds.contains(targetId) else { return false }
                var availableIds = groupIds
                availableIds.remove(targetId)
                guard validPlacement(change, availableIds: availableIds) else { return false }
            case .addItem:
                guard let parentId = change.parentId, groupIds.contains(parentId),
                      (itemCounts[parentId] ?? 0) < APP_MAX_ITEM_ROWS,
                      let referenceId = change.referenceId,
                      referenceIds.contains(referenceId) == false,
                      groupIds.contains(referenceId) == false,
                      itemParents[referenceId] == nil,
                      hasUsableName(change.name) else { return false }
                let siblingIds = Set(itemParents.compactMap { element in
                    element.value == parentId ? element.key : nil
                })
                guard validPlacement(change, availableIds: siblingIds) else { return false }
                referenceIds.insert(referenceId)
                itemParents[referenceId] = parentId
                itemCounts[parentId] = (itemCounts[parentId] ?? 0) + 1
            case .updateItem:
                guard let targetId = change.targetId, itemParents[targetId] != nil,
                      hasItemValues(change) else { return false }
                if change.name != nil, hasUsableName(change.name) == false { return false }
            case .deleteItem:
                guard let targetId = change.targetId, let parentId = itemParents.removeValue(forKey: targetId) else {
                    return false
                }
                itemCounts[parentId] = max(0, (itemCounts[parentId] ?? 1) - 1)
            case .moveItem:
                guard let targetId = change.targetId,
                      let sourceParentId = itemParents[targetId],
                      let parentId = change.parentId,
                      groupIds.contains(parentId) else { return false }
                if sourceParentId != parentId, APP_MAX_ITEM_ROWS <= (itemCounts[parentId] ?? 0) { return false }
                let siblingIds = Set(itemParents.compactMap { element in
                    element.key != targetId && element.value == parentId ? element.key : nil
                })
                guard validPlacement(change, availableIds: siblingIds) else { return false }
                if sourceParentId != parentId {
                    itemCounts[sourceParentId] = max(0, (itemCounts[sourceParentId] ?? 1) - 1)
                    itemCounts[parentId] = (itemCounts[parentId] ?? 0) + 1
                    itemParents[targetId] = parentId
                }
            }
        }
        return hasPack
    }

    static func hasUsableName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func hasItemValues(_ change: PackChangeDTO) -> Bool {
        change.name != nil || change.memo != nil || change.check != nil
            || change.stock != nil || change.need != nil || change.weight != nil
    }

    static func validPlacement(_ change: PackChangeDTO, availableIds: Set<String>) -> Bool {
        switch change.placement {
        case .head, .tail:
            return change.afterId == nil
        case .after:
            guard let afterId = change.afterId else { return false }
            return availableIds.contains(afterId)
        case nil:
            return false
        }
    }

    static func resolveGroup(_ identifier: String?,
                             in pack: M1Pack,
                             references: [String: M2Group]) -> M2Group? {
        guard let identifier else { return nil }
        return references[identifier] ?? pack.child.first { $0.id == identifier }
    }

    static func resolveItem(_ identifier: String?,
                            in pack: M1Pack,
                            references: [String: M3Item]) -> M3Item? {
        guard let identifier else { return nil }
        return references[identifier]
            ?? pack.child.lazy.flatMap(\.child).first { $0.id == identifier }
    }

    static func reorderGroup(_ group: M2Group,
                             in pack: M1Pack,
                             placement: PackChangeDTO.Placement?,
                             afterId: String?,
                             referencedGroups: [String: M2Group]) {
        var ordered = pack.child
            .filter { $0.id != group.id }
            .sorted { $0.order < $1.order }
        let index = insertionIndex(
            placement: placement,
            afterId: afterId,
            count: ordered.count,
            anchorIndex: { identifier in
                let anchor = referencedGroups[identifier] ?? ordered.first { $0.id == identifier }
                return anchor.flatMap { value in ordered.firstIndex { $0.id == value.id } }
            }
        )
        ordered.insert(group, at: index)
        normalizeSparseOrders(ordered)
    }

    static func reorderItem(_ item: M3Item,
                            in group: M2Group,
                            placement: PackChangeDTO.Placement?,
                            afterId: String?,
                            referencedItems: [String: M3Item]) {
        var ordered = group.child
            .filter { $0.id != item.id }
            .sorted { $0.order < $1.order }
        let index = insertionIndex(
            placement: placement,
            afterId: afterId,
            count: ordered.count,
            anchorIndex: { identifier in
                let anchor = referencedItems[identifier] ?? ordered.first { $0.id == identifier }
                return anchor.flatMap { value in ordered.firstIndex { $0.id == value.id } }
            }
        )
        ordered.insert(item, at: index)
        normalizeSparseOrders(ordered)
    }

    static func insertionIndex(placement: PackChangeDTO.Placement?,
                               afterId: String?,
                               count: Int,
                               anchorIndex: (String) -> Int?) -> Int {
        switch placement {
        case .head:
            return 0
        case .tail:
            return count
        case .after:
            guard let afterId, let index = anchorIndex(afterId) else { return count }
            return min(index + 1, count)
        case nil:
            return count
        }
    }

    static func sanitizedName(_ value: String) -> String {
        Sanitizer.clampedName(value)
    }

    static func sanitizedMemo(_ value: String) -> String {
        Sanitizer.clampedMemo(value)
    }

    static func clamped(_ value: Int, upperBound: Int) -> Int {
        min(max(0, value), upperBound)
    }
}

// MARK: - Sanitization Layer (Fix 5)

private extension PackImporter {

    // ─── サニタイズ済み中間表現 ───────────────────────────────────────────
    // PackJsonDTO をそのまま使うと「クランプ済みかどうか」が呼び出し側でわからない。
    // 中間構造体に変換することで、PackImporter 内部のロジックは「サニタイズ済み」
    // という不変条件のもとで動作できるようになる。
    // ─────────────────────────────────────────────────────────────────────

    /// PackJsonDTO をサニタイズして安全な値に正規化した中間表現
    struct SanitizedDTO {
        let name: String
        let memo: String
        let createdAt: Date
        let groups: [SanitizedGroup]

        struct SanitizedGroup {
            let name: String
            let memo: String
            let items: [SanitizedItem]
        }

        struct SanitizedItem {
            let name: String
            let memo: String
            let check: Bool
            let stock: Int
            let need: Int
            let weight: Int
        }

        /// PackJsonDTO から構築。すべてのフィールドをクランプ・切り詰めする
        init(from dto: PackJsonDTO) {
            self.name = Sanitizer.clampedName(dto.name)
            self.memo = Sanitizer.clampedMemo(dto.memo)
            self.createdAt = Sanitizer.clampedDate(dto.createdAt)

            // === グループのソート＋件数制限 ===
            // 1. 入力配列を index 付きにして order/index で安定ソート
            //    （order があれば order で、なければ元の index で比較。
            //    同値時は index でタイブレークすることで JSON の並びを忠実に再現する）
            // 2. 件数を APP_MAX_PART_ROWS に制限（超過分は単純に切り捨て）
            // 3. 各グループ内の Item も同様にサニタイズ
            let sortedGroups = dto.groups
                .enumerated()
                .sorted { left, right in
                    let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
                    let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
                    if leftOrder == rightOrder {
                        return left.offset < right.offset
                    }
                    return leftOrder < rightOrder
                }
                .map { $0.element }
                .prefix(APP_MAX_PART_ROWS)

            self.groups = sortedGroups.map { groupDTO in
                let items = groupDTO.items
                    .enumerated()
                    .sorted { left, right in
                        let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
                        let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
                        if leftOrder == rightOrder {
                            return left.offset < right.offset
                        }
                        return leftOrder < rightOrder
                    }
                    .map { $0.element }
                    .prefix(APP_MAX_ITEM_ROWS)
                    .map { item in
                        SanitizedItem(
                            name: Sanitizer.clampedName(item.name),
                            memo: Sanitizer.clampedMemo(item.memo),
                            check: item.check,
                            // 新フォーマットでは取り込み時に stock を 0 にリセットするのが原則。
                            // バックアップ復元時のみ元の値を尊重するが、念のため範囲クランプは実施する。
                            stock: Sanitizer.clampedStock(item.stock ?? 0),
                            need: Sanitizer.clampedNeed(item.need),
                            weight: Sanitizer.clampedWeight(item.weight)
                        )
                    }
                return SanitizedGroup(
                    name: Sanitizer.clampedName(groupDTO.name),
                    memo: Sanitizer.clampedMemo(groupDTO.memo),
                    items: Array(items)
                )
            }
        }
    }

    // ─── 個別フィールドのクランプ用ヘルパー ─────────────────────────────────
    // すべて `static` で副作用を持たないため、テストも書きやすい。
    // 命名規則：clamped○○○ で「安全な範囲に収めた値」を返す関数群とする。
    // ─────────────────────────────────────────────────────────────────────

    enum Sanitizer {

        /// 名前の長さを APP_MAX_NAME_LEN にクランプする
        /// - 制御文字や改行は残す（編集画面で見えるようにユーザーが直せる前提）
        static func clampedName(_ s: String) -> String {
            // Swift の Character 単位で先頭から切り出す。これにより絵文字や
            // 結合文字でも「文字数」のセマンティクスを保ったまま切り詰められる。
            if s.count <= APP_MAX_NAME_LEN {
                return s
            }
            return String(s.prefix(APP_MAX_NAME_LEN))
        }

        /// メモの長さを APP_MAX_MEMO_LEN にクランプする
        static func clampedMemo(_ s: String) -> String {
            if s.count <= APP_MAX_MEMO_LEN {
                return s
            }
            return String(s.prefix(APP_MAX_MEMO_LEN))
        }

        /// 在庫数を 0…APP_MAX_STOCK_NUM の範囲にクランプする
        /// - 負数 → 0、上限超過 → APP_MAX_STOCK_NUM
        static func clampedStock(_ n: Int) -> Int {
            min(max(0, n), APP_MAX_STOCK_NUM)
        }

        /// 必要数を 0…APP_MAX_NEED_NUM の範囲にクランプする
        static func clampedNeed(_ n: Int) -> Int {
            min(max(0, n), APP_MAX_NEED_NUM)
        }

        /// 個重量を 0…APP_MAX_WEIGHT_NUM の範囲にクランプする
        /// - 負の weight は物理的にあり得ないので 0 へ寄せる
        /// - 数百 kg 級の単品は実用上ありえないが、上限 999999g（≒ 1 トン）で防御
        static func clampedWeight(_ n: Int) -> Int {
            min(max(0, n), APP_MAX_WEIGHT_NUM)
        }

        /// 作成日時を妥当な範囲に補正する
        /// - 未来日付や極端に古い日付（1970 年以前など）が入った JSON から保護する
        /// - 範囲外の場合は現在時刻にフォールバック
        static func clampedDate(_ date: Date) -> Date {
            // 1990-01-01 以前と現在+1年以降は不自然なので現在時刻にフォールバック
            let lowerBound = Date(timeIntervalSince1970: 631_152_000) // 1990-01-01 00:00:00 UTC
            let upperBound = Date().addingTimeInterval(365 * 24 * 60 * 60)
            if date < lowerBound || upperBound < date {
                return Date()
            }
            return date
        }

        // ─── ソート ──────────────────────────────────────────────────────
        // ソートロジックは PackJsonDTO.Group / PackJsonDTO.Group.Item 両方で
        // 必要だが、ジェネリック化すると Swift の型推論に難があるため
        // SanitizedDTO.init 内でインラインで書いている（コードは若干重複するが、
        // ロジック自体は単純で読みやすさ重視）。
        // ─────────────────────────────────────────────────────────────────
    }
}
