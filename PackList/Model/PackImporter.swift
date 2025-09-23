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

        let groups = dto.groups.sorted { $0.order < $1.order }
        for (groupIndex, groupDTO) in groups.enumerated() {
            let group = M2Group(
                name: groupDTO.name,
                memo: groupDTO.memo,
                order: groupIndex,
                parent: pack
            )
            context.insert(group)
            pack.child.append(group)

            let items = groupDTO.items.sorted { $0.order < $1.order }
            for (itemIndex, itemDTO) in items.enumerated() {
                let item = M3Item(
                    name: itemDTO.name,
                    memo: itemDTO.memo,
                    check: itemDTO.check,
                    stock: itemDTO.stock,
                    need: itemDTO.need,
                    weight: itemDTO.weight,
                    order: itemIndex,
                    parent: group
                )
                context.insert(item)
                group.child.append(item)
            }
        }

        return pack
    }
}
