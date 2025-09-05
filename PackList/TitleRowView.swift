//
//  TitleRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct TitleRowView: View {
    @Environment(\.modelContext) private var modelContext
    let title: M1Title
    let isNew: Bool
    @Binding var lastAddedTitleID: M1Title.ID?
    @State private var isExpanded = false
    @State private var editingTitle: M1Title?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
    @State private var lastAddedGroupID: M2Group.ID?
    @State private var isHighlighted: Bool
    private let rowHeight: CGFloat = 44

    init(title: M1Title, isNew: Bool = false, lastAddedTitleID: Binding<M1Title.ID?> = .constant(nil)) {
        self.title = title
        self.isNew = isNew
        self._lastAddedTitleID = lastAddedTitleID
        _isHighlighted = State(initialValue: isNew)
    }

    private var allItemsChecked: Bool {
        let items = title.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check }
    }

    var body: some View {
        Group {
            HStack {
                Button {
                    isExpanded.toggle()
                    if isExpanded && title.child.isEmpty {
                        addGroup()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Image(systemName: "bag")
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.name.isEmpty ? "New Title" : title.name)
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(title.name.isEmpty ? .secondary : COLOR_NAME)
                    
                    if !title.note.isEmpty {
                        Text(title.note)
                            .lineLimit(3)
                            .font(FONT_NOTE)
                            .foregroundStyle(COLOR_NOTE)
                            .padding(.leading, 25)
                    }
                    
                    HStack {
                        Image(systemName: allItemsChecked ? "checkmark.circle" : "circle.dotted")
                            .controlSize(.small)
                        Spacer() // 右寄せにするため
                        //Text("在庫:\(title.stockWeight)g　必要:\(title.needWeight)g")
                        Text("\(title.stockWeight)g／\(title.needWeight)g")
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)
                            .padding(.trailing, 8)
                    }
                }
                Spacer()
                Button {
                    if !isExpanded {
                        isExpanded = true
                    }
                    addGroup()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .frame(minHeight: rowHeight)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleteTitle() } label: {
                    Image(systemName: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { copyTitle() } label: {
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
                editingTitle = title
            }
            .popover(item: $editingTitle, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { title in
                EditTitleView(title: title)
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
                ForEach(title.child) { group in
                    GroupRowView(group: group, isNew: group.id == lastAddedGroupID, lastAddedGroupID: $lastAddedGroupID)
                }
            }
        }
    }

    private func addGroup() {
        let newGroup = M2Group(name: "", parent: title)
        modelContext.insert(newGroup)
        title.child.append(newGroup)
        lastAddedGroupID = newGroup.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedGroupID = nil
        }
    }

    private func deleteTitle() {
        for group in title.child {
            deleteGroup(group)
        }
        modelContext.delete(title)
    }

    private func deleteGroup(_ group: M2Group) {
        for item in group.child {
            modelContext.delete(item)
        }
        modelContext.delete(group)
    }

    private func copyTitle() {
        let newTitle = M1Title(name: title.name, note: title.note, createdAt: title.createdAt.addingTimeInterval(-0.001))
        modelContext.insert(newTitle)
        for group in title.child {
            copyGroup(group, to: newTitle)
        }
        lastAddedTitleID = newTitle.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedTitleID = nil
        }
    }

    private func copyGroup(_ group: M2Group, to parent: M1Title) {
        let newGroup = M2Group(name: group.name, note: group.note, parent: parent)
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
        let newItem = M3Item(name: item.name, note: item.note, stock: item.stock, need: item.need, weight: item.weight, parent: parent)
        modelContext.insert(newItem)
        if let index = parent.child.firstIndex(where: { $0.id == item.id }) {
            parent.child.insert(newItem, at: index + 1)
        } else {
            parent.child.append(newItem)
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

struct EditTitleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var title: M1Title
    
    var body: some View {
        VStack {
            HStack {
                Text("タイトル:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $title.name)
                    .lineLimit(3)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
            }
            HStack {
                Text("メモ:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $title.note)
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

