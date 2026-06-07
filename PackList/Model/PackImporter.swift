//
//  PackImporter.swift
//  PackList
//
//  Created by sumpo on 2025/09/23.
//

import Foundation
import SwiftData

struct PackImporter {
    @discardableResult
    static func insertPack(from dto: PackJsonDTO, into context: ModelContext, order: Int) -> M1Pack {
        let pack = M1Pack(
            name: dto.name,
            memo: dto.memo,
            createdAt: dto.createdAt,
            order: order
        )
        context.insert(pack)

        // JSON上の順序情報は省略され得るため、indexで安定ソートする
        let groups = dto.groups.enumerated().sorted { left, right in
            let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
            let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
            if leftOrder == rightOrder {
                // 同一orderが付与されているとsorted(by:)は安定ではないので、元の並び順(index)で優先順位を決める
                return left.offset < right.offset
            }
            return leftOrder < rightOrder
        }.map { $0.element }

        for (groupIndex, groupDTO) in groups.enumerated() {
            let group = M2Group(
                name: groupDTO.name,
                memo: groupDTO.memo,
                order: groupIndex * ORDER_SPARSE,
                parent: pack
            )
            context.insert(group)
            pack.child.append(group)

            let items = groupDTO.items.enumerated().sorted { left, right in
                let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
                let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
                if leftOrder == rightOrder {
                    // JSONの順番を信用して復元するため、orderが同値なら入力順(index)を優先する
                    return left.offset < right.offset
                }
                return leftOrder < rightOrder
            }.map { $0.element }

            for (itemIndex, itemDTO) in items.enumerated() {
                let item = M3Item(
                    name: itemDTO.name,
                    memo: itemDTO.memo,
                    check: itemDTO.check,
                    stock: itemDTO.stock ?? 0, // 新フォーマットでは在庫は常にアプリ側で初期化
                    need: itemDTO.need,
                    weight: itemDTO.weight,
                    order: itemIndex * ORDER_SPARSE,
                    parent: group
                )
                context.insert(item)
                group.child.append(item)
            }
        }

        return pack
    }

    @discardableResult
    static func overwrite(pack: M1Pack, with dto: PackJsonDTO, in context: ModelContext) -> M1Pack {
        // 既存のパック情報をDTOに合わせて更新し、同じIDとorderを保ったまま差し替える
        pack.name = dto.name
        pack.memo = dto.memo
        pack.createdAt = dto.createdAt

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

        // JSON上の順序は省略されることもあるので、insert時と同じく並び替えてから採番する
        let groups = dto.groups.enumerated().sorted { left, right in
            let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
            let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
            if leftOrder == rightOrder {
                // 上書き時も入力JSONの順番を崩さないよう、indexでタイブレークする
                return left.offset < right.offset
            }
            return leftOrder < rightOrder
        }.map { $0.element }

        for (groupIndex, groupDTO) in groups.enumerated() {
            let group = M2Group(
                name: groupDTO.name,
                memo: groupDTO.memo,
                order: groupIndex * ORDER_SPARSE,
                parent: pack
            )
            context.insert(group)
            pack.child.append(group)

            let items = groupDTO.items.enumerated().sorted { left, right in
                let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
                let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
                if leftOrder == rightOrder {
                    // タイブレークでindexを採用し、エクスポート時の並びをそのまま復元する
                    return left.offset < right.offset
                }
                return leftOrder < rightOrder
            }.map { $0.element }

            for (itemIndex, itemDTO) in items.enumerated() {
                let item = M3Item(
                    name: itemDTO.name,
                    memo: itemDTO.memo,
                    check: itemDTO.check,
                    stock: itemDTO.stock ?? 0,
                    need: itemDTO.need,
                    weight: itemDTO.weight,
                    order: itemIndex * ORDER_SPARSE,
                    parent: group
                )
                context.insert(item)
                group.child.append(item)
            }
        }

        return pack
    }
}
