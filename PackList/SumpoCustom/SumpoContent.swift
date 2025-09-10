//
//  SumpoContent.swift
//  PackList
//
//  Created by Sum Positive on 2025/09/10.
//

import SwiftUI

// 例データ型
struct NodeData: Hashable {
    var title: String
    var note: String = ""
}

struct DemoPinnedTreeCompatView: View {
    @StateObject private var vm = PinnedTreeViewModel<NodeData>([
        .init(data: .init(title: "Pack A"), children: [
            .init(data: .init(title: "Group A-1"), children: [
                .init(data: .init(title: "Item A-1-1")),
                .init(data: .init(title: "Item A-1-2")),
            ]),
            .init(data: .init(title: "Group A-2"), children: [
                .init(data: .init(title: "Item A-2-1")),
                .init(data: .init(title: "Item A-2-2")),
                .init(data: .init(title: "Item A-2-3")),
                .init(data: .init(title: "Item A-2-4")),
                .init(data: .init(title: "Item A-2-5")),
            ]),
        ]),
        .init(data: .init(title: "Pack B"), children: [
            .init(data: .init(title: "Group B-1"), children: [
                .init(data: .init(title: "Item B-1-1")),
                .init(data: .init(title: "Item B-1-2")),
            ]),
        ]),
    ])
    
    var body: some View {
        PinnedTreeView(
            vm: vm,
            title: { node in erase(Text(node.data.title)) },
            subtitle: { node in
                node.children.isEmpty
                ? erase(Text(node.data.note.isEmpty ? "Leaf" : node.data.note))
                : erase(Text("\(node.children.count) 個の子"))
            },
            leafContent: { node in
                erase(HStack {
                    Text(node.data.title)
                    if !node.data.note.isEmpty {
                        Text(node.data.note).font(.caption).foregroundStyle(.secondary)
                    }
                })
            },
            onCreateChild: { path in
                vm.addChild(.init(data: .init(title: "New Node")), to: path)
            },
            onRename: { path in
                guard var n = vm.node(at: path) else { return }
                n.data.title += " *"
                vm.setNode(n, at: path)
            },
            onDelete: { path in
                vm.delete(at: path)
            }
        )
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
