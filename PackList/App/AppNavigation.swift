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
    case itemEdit(packID: M1Pack.ID, groupID: M2Group.ID, itemID: M3Item.ID)

    private enum CodingKeys: String, CodingKey {
        case caseName
        case packID
        case groupID
        case itemID
    }

    private enum CaseName: String, Codable {
        case groupList
        case itemList
        case itemEdit
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
        case .itemEdit(let packID, let groupID, let itemID):
            try container.encode(CaseName.itemEdit, forKey: .caseName)
            try container.encode(packID, forKey: .packID)
            try container.encode(groupID, forKey: .groupID)
            try container.encode(itemID, forKey: .itemID)
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
            self = .itemEdit(packID: packID, groupID: groupID, itemID: itemID)
        }
    }
}

final class NavigationCoordinator: ObservableObject {
    @Published var path = NavigationPath()
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
            Text("navigation.packNotFound")
        }
    }
}

struct ItemListScene: View {
    let packID: M1Pack.ID
    let groupID: M2Group.ID

    @Query private var packs: [M1Pack]
    @Query private var groups: [M2Group]

    init(packID: M1Pack.ID, groupID: M2Group.ID) {
        self.packID = packID
        self.groupID = groupID
        _packs = Query(filter: #Predicate<M1Pack> { $0.id == packID })
        _groups = Query(filter: #Predicate<M2Group> { $0.id == groupID })
    }

    var body: some View {
        if let pack = packs.first, let group = groups.first {
            ItemListView(pack: pack, initialGroup: group)
        } else {
            Text("navigation.groupNotFound")
        }
    }
}

struct ItemEditScene: View {
    let packID: M1Pack.ID
    let groupID: M2Group.ID
    let itemID: M3Item.ID

    @Environment(\.dismiss) private var dismiss
    @Query private var packs: [M1Pack]
    @Query private var groups: [M2Group]
    @Query private var items: [M3Item]

    init(packID: M1Pack.ID, groupID: M2Group.ID, itemID: M3Item.ID) {
        self.packID = packID
        self.groupID = groupID
        self.itemID = itemID
        _packs = Query(filter: #Predicate<M1Pack> { $0.id == packID })
        _groups = Query(filter: #Predicate<M2Group> { $0.id == groupID })
        _items = Query(filter: #Predicate<M3Item> { $0.id == itemID })
    }

    var body: some View {
        if let pack = packs.first,
           let group = groups.first,
           let item = items.first {
            ItemEditNavigationContent(
                pack: pack,
                group: group,
                item: item,
                onDismiss: { dismiss() }
            )
        } else {
            Text("navigation.itemNotFound")
        }
    }
}

private struct ItemEditNavigationContent: View {
    let pack: M1Pack
    let group: M2Group
    @Bindable var item: M3Item
    let onDismiss: () -> Void

    init(pack: M1Pack, group: M2Group, item: M3Item, onDismiss: @escaping () -> Void) {
        self.pack = pack
        self.group = group
        self._item = Bindable(item)
        self.onDismiss = onDismiss
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    pack.name.placeholderText("placeholder.pack.new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    group.name.placeholderText("placeholder.group.new")
                        .font(.headline)
                }

                ItemEditView(item: item, style: .navigation) {
                    onDismiss()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(item.name.placeholderText("placeholder.item.new"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
