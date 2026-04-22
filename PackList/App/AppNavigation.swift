//
//  AppNavigation.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//

import Foundation
import SwiftUI
import SwiftData

enum AppDestination: Hashable, Codable {
    case groupList(packID: M1Pack.ID)
    case itemList(packID: M1Pack.ID, groupID: M2Group.ID)
    case itemEdit(packID: M1Pack.ID, groupID: M2Group.ID, itemID: M3Item.ID, sort: ItemSortOption?)
    case itemSortList(packID: M1Pack.ID, sort: ItemSortOption)

    private enum CodingKeys: String, CodingKey {
        case caseName
        case packID
        case groupID
        case itemID
        case sort
    }

    private enum CaseName: String, Codable {
        case groupList
        case itemList
        case itemEdit
        case itemSortList
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .groupList(let packID):
            try container.encode(CaseName.groupList, forKey: .caseName)
            try container.encode(packID, forKey: .packID)
        case .itemList(let packID, let groupID):
            try container.encode(CaseName.itemList, forKey: .caseName)
            try container.encode(packID, forKey: .packID)
            try container.encode(groupID, forKey: .groupID)
        case .itemEdit(let packID, let groupID, let itemID, let sort):
            try container.encode(CaseName.itemEdit, forKey: .caseName)
            try container.encode(packID, forKey: .packID)
            try container.encode(groupID, forKey: .groupID)
            try container.encode(itemID, forKey: .itemID)
            try container.encodeIfPresent(sort, forKey: .sort)
        case .itemSortList(let packID, let sort):
            try container.encode(CaseName.itemSortList, forKey: .caseName)
            try container.encode(packID, forKey: .packID)
            try container.encode(sort, forKey: .sort)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let caseName = try container.decode(CaseName.self, forKey: .caseName)
        switch caseName {
        case .groupList:
            let packID = try container.decode(M1Pack.ID.self, forKey: .packID)
            self = .groupList(packID: packID)
        case .itemList:
            let packID = try container.decode(M1Pack.ID.self, forKey: .packID)
            let groupID = try container.decode(M2Group.ID.self, forKey: .groupID)
            self = .itemList(packID: packID, groupID: groupID)
        case .itemEdit:
            let packID = try container.decode(M1Pack.ID.self, forKey: .packID)
            let groupID = try container.decode(M2Group.ID.self, forKey: .groupID)
            let itemID = try container.decode(M3Item.ID.self, forKey: .itemID)
            let sort = try container.decodeIfPresent(ItemSortOption.self, forKey: .sort)
            self = .itemEdit(packID: packID, groupID: groupID, itemID: itemID, sort: sort)
        case .itemSortList:
            let packID = try container.decode(M1Pack.ID.self, forKey: .packID)
            let sort = try container.decode(ItemSortOption.self, forKey: .sort)
            self = .itemSortList(packID: packID, sort: sort)
        }
    }
}

struct GroupListScene: View {
    let packID: M1Pack.ID

    @Query private var packs: [M1Pack]

    init(packID: M1Pack.ID) {
        self.packID = packID
        _packs = Query(filter: #Predicate<M1Pack> { $0.id == packID })
    }

    var body: some View {
        if let pack = packs.first {
            GroupListView(pack: pack)
        } else {
            Text("no.packs.found")
        }
    }
}

struct ItemListScene: View {
    let packID: M1Pack.ID
    let groupID: M2Group.ID

    @Query private var packs: [M1Pack]

    init(packID: M1Pack.ID, groupID: M2Group.ID) {
        self.packID = packID
        self.groupID = groupID
        _packs = Query(filter: #Predicate<M1Pack> { $0.id == packID })
    }

    var body: some View {
        if let pack = packs.first,
           let group = pack.child.first(where: { $0.id == groupID }) {
            ItemListView(pack: pack, group: group)
        } else {
            Text("no.groups.found")
        }
    }
}

struct ItemEditScene: View {
    let packID: M1Pack.ID
    let groupID: M2Group.ID
    let sort: ItemSortOption?

    @Environment(\.dismiss) private var dismiss
    @Query private var packs: [M1Pack]
    @Query private var groupItems: [M3Item]
    @State private var currentItemID: M3Item.ID

    init(packID: M1Pack.ID, groupID: M2Group.ID, itemID: M3Item.ID, sort: ItemSortOption?) {
        self.packID = packID
        self.groupID = groupID
        self.sort = sort
        _packs = Query(filter: #Predicate<M1Pack> { $0.id == packID })
        _groupItems = Query(
            filter: #Predicate<M3Item> { $0.parent?.id == groupID },
            sort: [SortDescriptor(\M3Item.order)]
        )
        _currentItemID = State(initialValue: itemID)
    }

    var body: some View {
        if let pack = packs.first,
           let item = resolvedItem,
           let group = item.parent ?? pack.child.first(where: { $0.id == groupID }) {
            ItemEditView(
                pack: pack,
                group: group,
                item: item,
                onDismiss: { dismiss() },
                onSelectItem: { selected in currentItemID = selected.id },
                adjacentItemProvider: sort == nil ? nil : { current, offset in
                    adjacentItem(from: current, offset: offset)
                }
            )
            .onAppear {
                if currentItemID != item.id {
                    currentItemID = item.id
                }
            }
        } else {
            Text("no.items.found")
        }
    }

    private var availableItems: [M3Item] {
        if let sort, let pack = packs.first {
            return sort.sortedItems(from: pack).filter { $0.parent != nil }
        }
        return groupItems
    }

    private var resolvedItem: M3Item? {
        let items = availableItems
        if let current = items.first(where: { $0.id == currentItemID }) {
            return current
        }
        return items.first
    }

    private func adjacentItem(from current: M3Item, offset: Int) -> M3Item? {
        guard offset != 0 else { return nil }
        let items = availableItems
        guard let currentIndex = items.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        let destinationIndex = currentIndex + offset
        guard items.indices.contains(destinationIndex) else {
            return nil
        }
        return items[destinationIndex]
    }
}

struct ItemSortListScene: View {
    let packID: M1Pack.ID
    let sort: ItemSortOption

    @Query private var packs: [M1Pack]

    init(packID: M1Pack.ID, sort: ItemSortOption) {
        self.packID = packID
        self.sort = sort
        _packs = Query(filter: #Predicate<M1Pack> { $0.id == packID })
    }

    var body: some View {
        if let pack = packs.first {
            ItemSortListView(pack: pack, sortOption: sort)
        } else {
            Text("no.packs.found")
        }
    }
}
