//
//  GroupRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct GroupRowView: View {
    @Environment(\.modelContext) private var modelContext
    let group: M2Group

    @State private var isExpanded = false
    @State private var editingGroup: M2Group?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom

    private let rowHeight: CGFloat = 44

    init(group: M2Group) {
        self.group = group
    }

    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check }
    }

    var body: some View {
        Section {
            if isExpanded {
                if group.child.isEmpty {
                    Text(" ")
                        .padding(.leading, 40)
                } else {
                    ForEach(sortedItems) { item in
                        ItemRowView(item: item)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    .onMove(perform: moveItem)
                    .environment(\.editMode, .constant(.active))
                    .animation(.default, value: group.child)
                }
            }
        } header: {
            HStack {
                Button {
                    isExpanded.toggle()
                    if isExpanded && group.child.isEmpty {
                        addItem()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(BorderlessButtonStyle())

                Image(systemName: allItemsChecked ? "checkmark.rectangle" : "rectangle")
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name.isEmpty ? "New Group" : group.name)
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(group.name.isEmpty ? .secondary : COLOR_NAME)

                    if !group.memo.isEmpty {
                        Text(group.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.leading, 25)
                    }
                    if DEBUG_SHOW_ORDER_ID {
                        Text("group (\(group.order)) [\(group.id)]")
                    }

                    HStack {
                        Spacer() // 右寄せにするため
                        if 0 < group.stockWeight {
                            Text("\(group.stockWeight)g／\(group.needWeight)g")
                                .font(FONT_WEIGHT)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.trailing, 4)
                        }
//                        Text("\(group.stock)／\(group.need)")
//                            .font(FONT_STOCK)
//                            .foregroundStyle(COLOR_WEIGHT)
//                            .padding(.trailing, 4)
                    }
                }
                Spacer()
                Button {
                    if !isExpanded {
                        isExpanded = true
                    }
                    addItem()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .frame(minHeight: rowHeight)
            .padding(.leading)
            .swipeActions(edge: .trailing) {
                Button("Cut") {
                    copyToClipboard()
                    deleteGroup()
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                Button("Copy") {
                    copyToClipboard()
                }
                .tint(.cyan)

                Button("Paste") {
                    pasteFromClipboard()
                }
                .disabled(RowClipboard.group == nil && RowClipboard.item == nil)
                .tint(.orange)

                Button("Duplicate") {
                    duplicateGroup()
                }
                .tint(.green)
            }
            .contentShape(Rectangle())
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { oldValue, newValue in
                            frame = newValue
                        }
                }
            )
            .onTapGesture {
                arrowEdge = arrowEdge(for: frame)
                editingGroup = group
            }
            .popover(item: $editingGroup, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { group in
                EditGroupView(group: group)
                    .presentationCompactAdaptation(.none)
                    .background(Color.primary.opacity(0.2))
            }
        }
    }

    private var sortedItems: [M3Item] {
        group.child.sorted { $0.order < $1.order }
    }

    private func addItem() {
        let newItem = M3Item(name: "", order: group.nextItemOrder(), parent: group)
        modelContext.insert(newItem)
        withAnimation {
            group.child.append(newItem)
            group.normalizeItemOrder()
        }
    }

    private func deleteGroup() {
        for item in group.child {
            modelContext.delete(item)
        }
        if let parent = group.parent,
           let index = parent.child.firstIndex(where: { $0.id == group.id }) {
            parent.child.remove(at: index)
            parent.normalizeGroupOrder()
        }
        modelContext.delete(group)
    }

    private func duplicateGroup() {
        guard let parentTitle = group.parent else { return }
        let newGroup = M2Group(name: group.name, memo: group.memo, order: parentTitle.nextGroupOrder(), parent: parentTitle)
        modelContext.insert(newGroup)
        withAnimation {
            if let index = parentTitle.child.firstIndex(where: { $0.id == group.id }) {
                parentTitle.child.insert(newGroup, at: index + 1)
            } else {
                parentTitle.child.append(newGroup)
            }
            parentTitle.normalizeGroupOrder()
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
    }

    private func copyToClipboard() {
        RowClipboard.clear()
        RowClipboard.group = cloneGroup(group)
    }

    private func pasteFromClipboard() {
        if let clip = RowClipboard.group, let parent = group.parent {
            // GroupRowを現在行にペーストする、現在行は下になる
            let newGroup = cloneGroup(clip, parent: parent)
            newGroup.order = group.order
            modelContext.insert(newGroup)
            withAnimation {
                // 現在行(index)を求めその行に追加する
                if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
                    // index位置に追加
                    parent.child.insert(newGroup, at: index)
                } else {
                    // 末尾に追加
                    parent.child.append(newGroup)
                }
                parent.normalizeGroupOrder()
            }
        }
        else if let clip = RowClipboard.item {
            // ItemRowをGroupの最上行に挿入する
            isExpanded = true
            let newItem = cloneItem(clip, parent: group)
            newItem.order = -1 // 最上行  group.nextItemOrder()
            modelContext.insert(newItem)
            withAnimation {
                group.child.insert(newItem, at: 0)
                group.normalizeItemOrder()
            }
        }
    }

    private func copyItem(_ item: M3Item, to parent: M2Group) {
        let newItem = M3Item(name: item.name, memo: item.memo, stock: item.stock, need: item.need, weight: item.weight, order: parent.nextItemOrder(), parent: parent)
        modelContext.insert(newItem)
        parent.child.append(newItem)
        parent.normalizeItemOrder()
    }

    private func moveItem(from source: IndexSet, to destination: Int) {
        var items = sortedItems
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.order = index
        }
        group.child = items
    }

    private func arrowEdge(for frame: CGRect?) -> Edge {
        guard let frame = frame else { return .bottom }
        let screenHeight = UIScreen.main.bounds.height
        let topSpace = frame.minY
        let bottomSpace = screenHeight - frame.maxY
        return bottomSpace > topSpace ? .top : .bottom
    }
}

struct EditGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var group: M2Group
    
    var body: some View {
        VStack {
            HStack {
                Text("名称:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $group.name, prompt: Text("New Group name"))
                    .lineLimit(3)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
            }
            HStack {
                Text("メモ:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $group.memo)
                    .lineLimit(3)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
            }
//            HStack {
//                Spacer()
//                Button("Done") {
//                    try? context.save()
//                    dismiss()
//                }
//            }
        }
        .padding()
        .frame(minWidth: 300)
        .onDisappear() {
            try? context.save()
        }
    }
}

