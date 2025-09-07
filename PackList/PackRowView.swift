//
//  PackRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct PackRowView: View {
    @Environment(\.modelContext) private var modelContext
    let pack: M1Pack
    let isNew: Bool
    @Binding var lastAddedPackID: M1Pack.ID?
    @State private var isExpanded = false
    @State private var editingPack: M1Pack?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
    @State private var lastAddedGroupID: M2Group.ID?
    @State private var isHighlighted: Bool
    @State private var draggingItem: M3Item?
    private let rowHeight: CGFloat = 44

    init(pack: M1Pack, isNew: Bool = false, lastAddedPackID: Binding<M1Pack.ID?> = .constant(nil)) {
        self.pack = pack
        self.isNew = isNew
        self._lastAddedPackID = lastAddedPackID
        _isHighlighted = State(initialValue: isNew)
    }

    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check }
    }

    var body: some View {
        Group {
            HStack {
                Button {
                    isExpanded.toggle()
                    if isExpanded && pack.child.isEmpty {
                        addGroup()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Image(systemName: allItemsChecked ? "checkmark.message" : "message")
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(pack.name.isEmpty ? "New Pack" : pack.name)
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(pack.name.isEmpty ? .secondary : COLOR_NAME)
                    
                    if !pack.memo.isEmpty {
                        Text(pack.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.leading, 25)
                    }
                    
                    HStack {
                        Spacer() // 右寄せにするため
                        if 0 < pack.stockWeight {
                            Text("\(pack.stockWeight)g／\(pack.needWeight)g")
                                .font(FONT_WEIGHT)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.trailing, 4)
                        }
//                        Text("［\(pack.stock)／\(pack.need)］")
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
                    addGroup()
                } label: {
                    Image(systemName: "plus.rectangle")
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .frame(minHeight: rowHeight)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deletePack() } label: {
                    Image(systemName: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { copyPack() } label: {
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
                editingPack = pack
            }
            .popover(item: $editingPack, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { title in
                EditPackView(pack: title)
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
                ForEach(pack.child) { group in
                    GroupRowView(group: group,
                                 isNew: group.id == lastAddedGroupID,
                                 lastAddedGroupID: $lastAddedGroupID,
                                 draggingItem: $draggingItem)
                }
            }
        }
    }

    private func addGroup() {
        let newGroup = M2Group(name: "", parent: pack)
        modelContext.insert(newGroup)
        pack.child.append(newGroup)
        lastAddedGroupID = newGroup.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedGroupID = nil
        }
    }

    private func deletePack() {
        for group in pack.child {
            deleteGroup(group)
        }
        modelContext.delete(pack)
    }

    private func deleteGroup(_ group: M2Group) {
        for item in group.child {
            modelContext.delete(item)
        }
        modelContext.delete(group)
    }

    private func copyPack() {
        let newTitle = M1Pack(name: pack.name, memo: pack.memo, createdAt: pack.createdAt.addingTimeInterval(-0.001))
        modelContext.insert(newTitle)
        for group in pack.child {
            copyGroup(group, to: newTitle)
        }
        lastAddedPackID = newTitle.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedPackID = nil
        }
    }

    private func copyGroup(_ group: M2Group, to parent: M1Pack) {
        let newGroup = M2Group(name: group.name, memo: group.memo, parent: parent)
        modelContext.insert(newGroup)
        if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
            parent.child.insert(newGroup, at: index + 1)
        } else {
            parent.child.append(newGroup)
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
        let newItem = M3Item(name: item.name, memo: item.memo, stock: item.stock, need: item.need, weight: item.weight, order: parent.nextItemOrder(), parent: parent)
        modelContext.insert(newItem)
        parent.child.append(newItem)
        parent.normalizeItemOrder()
    }

    private func arrowEdge(for frame: CGRect?) -> Edge {
        guard let frame = frame else { return .bottom }
        let screenHeight = UIScreen.main.bounds.height
        let topSpace = frame.minY
        let bottomSpace = screenHeight - frame.maxY
        return bottomSpace > topSpace ? .top : .bottom
    }
}

struct EditPackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var pack: M1Pack
    
    var body: some View {
        VStack {
            HStack {
                Text("名称:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $pack.name, prompt: Text("New Pack name"))
                    .lineLimit(3)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
            }
            HStack {
                Text("メモ:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $pack.memo)
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
        .frame(minWidth: 300, maxHeight: 300)
        .onDisappear() {
            try? context.save()
        }
    }
}

