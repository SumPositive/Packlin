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
}
