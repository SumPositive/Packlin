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
    let isNew: Bool
    @Binding var lastAddedGroupID: M2Group.ID?
    @State private var isExpanded = false
    @State private var editingGroup: M2Group?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
    @State private var lastAddedItemID: M3Item.ID?
    @State private var isHighlighted: Bool
    private let rowHeight: CGFloat = 44

    init(group: M2Group, isNew: Bool = false, lastAddedGroupID: Binding<M2Group.ID?> = .constant(nil)) {
        self.group = group
        self.isNew = isNew
        self._lastAddedGroupID = lastAddedGroupID
        _isHighlighted = State(initialValue: isNew)
    }

    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check }
    }

    var body: some View {
        Group {
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

                    HStack {
                        Spacer() // 右寄せにするため
                        //Text("在庫:\(group.stockWeight)g　必要:\(group.needWeight)g")
//                        Text("［\(group.stock)／\(group.need)］")
//                            .font(FONT_STOCK)
//                            .foregroundStyle(COLOR_WEIGHT)
//                            .padding(.trailing, 4)
                        Text("\(group.stockWeight)g／\(group.needWeight)g")
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)
                            .padding(.trailing, 4)
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
                Button(role: .destructive) { deleteGroup() } label: {
                    Image(systemName: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { copyGroup() } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
            .contentShape(Rectangle())
            .background(isHighlighted ? Color.green.opacity(0.2) : Color.clear)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { frame = $0 }
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
            .onAppear {
                if isNew {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isHighlighted = false
                        }
                    }
                }
            }

            if isExpanded {
                if group.child.isEmpty {
                    Text(" ")
                        .padding(.leading, 40)
                } else {
                    ForEach(group.child) { item in
                        ItemRowView(item: item, isNew: item.id == lastAddedItemID, lastAddedItemID: $lastAddedItemID)
                    }
                }
            }
        }
    }

    private func addItem() {
        let newItem = M3Item(name: "", parent: group)
        modelContext.insert(newItem)
        group.child.append(newItem)
        lastAddedItemID = newItem.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedItemID = nil
        }
    }

    private func deleteGroup() {
        for item in group.child {
            modelContext.delete(item)
        }
        modelContext.delete(group)
    }

    private func copyGroup() {
        guard let parentTitle = group.parent else { return }
        let newGroup = M2Group(name: group.name, memo: group.memo, parent: parentTitle)
        modelContext.insert(newGroup)
        if let index = parentTitle.child.firstIndex(where: { $0.id == group.id }) {
            parentTitle.child.insert(newGroup, at: index + 1)
        } else {
            parentTitle.child.append(newGroup)
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
        lastAddedGroupID = newGroup.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedGroupID = nil
        }
    }

    private func copyItem(_ item: M3Item, to parent: M2Group) {
        let newItem = M3Item(name: item.name, memo: item.memo, stock: item.stock, need: item.need, weight: item.weight, parent: parent)
        modelContext.insert(newItem)
        if let index = parent.child.firstIndex(where: { $0.id == item.id }) {
            parent.child.insert(newItem, at: index + 1)
        } else {
            parent.child.append(newItem)
        }
        lastAddedItemID = newItem.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedItemID = nil
        }
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

