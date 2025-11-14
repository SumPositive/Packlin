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

        // 旧データが混ざらないように、先にグループ以下を完全削除しておく
        let existingGroups = pack.child
        for group in existingGroups {
            context.delete(group)
        }
        pack.child.removeAll()

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
