import Foundation
import SwiftData

enum RowClipboard {
    static var pack: M1Pack?
    static var group: M2Group?
    static var item: M3Item?

    static func clear() {
        pack = nil
        group = nil
        item = nil
    }
}

func clonePack(_ source: M1Pack) -> M1Pack {
    let newPack = M1Pack(name: source.name,
                         memo: source.memo,
                         createdAt: source.createdAt,
                         order: source.order,
                         isExpanded: source.isExpanded)
    for g in source.child {
        let newGroup = cloneGroup(g, parent: newPack)
        newPack.child.append(newGroup)
    }
    return newPack
}

func cloneGroup(_ source: M2Group, parent: M1Pack? = nil) -> M2Group {
    let newGroup = M2Group(name: source.name,
                           memo: source.memo,
                           order: source.order,
                           parent: parent,
                           isExpanded: source.isExpanded)
    for i in source.child {
        let newItem = cloneItem(i, parent: newGroup)
        newGroup.child.append(newItem)
    }
    return newGroup
}

func cloneItem(_ source: M3Item, parent: M2Group? = nil, parentItem: M3Item? = nil) -> M3Item {
    let newItem = M3Item(name: source.name,
                         memo: source.memo,
                         check: source.check,
                         stock: source.stock,
                         need: source.need,
                         weight: source.weight,
                         order: source.order,
                         parent: parent,
                         parentItem: parentItem,
                         isExpanded: source.isExpanded)
    for c in source.child {
        let childItem = cloneItem(c, parent: parent, parentItem: newItem)
        newItem.child.append(childItem)
    }
    return newItem
}
