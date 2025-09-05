//
//  ContentView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\M1Title.createdAt, order: .reverse)]) private var titles: [M1Title]
    @State private var expandedTitles: Set<PersistentIdentifier> = []
    @State private var expandedGroups: Set<PersistentIdentifier> = []
    @State private var editingTitle: M1Title?
    @State private var editingGroup: M2Group?
    @State private var editingItem: M3Item?
    @State private var titleFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var groupFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var itemFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var titleArrowEdge: Edge = .bottom
    @State private var groupArrowEdge: Edge = .bottom
    @State private var itemArrowEdge: Edge = .bottom
    private let rowHeight: CGFloat = 44

    var body: some View {
        NavigationView {
            List {
                ForEach(titles) { title in
                    Group {
                        HStack {
                            Button {
                                toggleTitle(title)
                            } label: {
                                Image(systemName: expandedTitles.contains(title.id) ? "chevron.down" : "chevron.right")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            // Title
                            Image(systemName: "bag")
                            Text(title.name.isEmpty ? "New Title" : title.name)
                                .foregroundStyle(title.name.isEmpty ? .secondary : .primary)
                            Spacer()
                            Button {
                                addGroup(to: title)
                            } label: {
                                // +Group
                                Image(systemName: "folder.badge.plus")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .frame(height: rowHeight)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTitle(title)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                copyTitle(title)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .contentShape(Rectangle())
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { titleFrames[title.id] = proxy.frame(in: .global) }
                                    .onChange(of: proxy.frame(in: .global)) { newFrame in
                                        titleFrames[title.id] = newFrame
                                    }
                            }
                        )
                        .onTapGesture {
                            titleArrowEdge = arrowEdge(for: titleFrames[title.id])
                            editingTitle = title
                        }
                        .popover(item: Binding(
                            get: { editingTitle?.id == title.id ? editingTitle : nil },
                            set: { editingTitle = $0 }
                        ), attachmentAnchor: .rect(.bounds), arrowEdge: titleArrowEdge) { title in
                            EditTitleView(title: title)
                                .presentationCompactAdaptation(.none)
                        }

                        if expandedTitles.contains(title.id) {
                            ForEach(title.child) { group in
                                Group {
                                    HStack {
                                        Button {
                                            toggleGroup(group)
                                        } label: {
                                            Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        // Group
                                        Image(systemName: "folder")
                                        Text(group.name.isEmpty ? "New Group" : group.name)
                                            .foregroundStyle(group.name.isEmpty ? .secondary : .primary)
                                        Spacer()
                                        Button {
                                            addItem(to: group)
                                        } label: {
                                            // ＋Item
                                            Image(systemName: "plus.app")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                    .frame(height: rowHeight)
                                    .padding(.leading)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteGroup(group)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            copyGroup(group)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .background(
                                        GeometryReader { proxy in
                                            Color.clear
                                                .onAppear { groupFrames[group.id] = proxy.frame(in: .global) }
                                                .onChange(of: proxy.frame(in: .global)) { newFrame in
                                                    groupFrames[group.id] = newFrame
                                                }
                                        }
                                    )
                                    .onTapGesture {
                                        groupArrowEdge = arrowEdge(for: groupFrames[group.id])
                                        editingGroup = group
                                    }
                                    .popover(item: Binding(
                                        get: { editingGroup?.id == group.id ? editingGroup : nil },
                                        set: { editingGroup = $0 }
                                    ), attachmentAnchor: .rect(.bounds), arrowEdge: groupArrowEdge) { group in
                                        EditGroupView(group: group)
                                            .presentationCompactAdaptation(.none)
                                    }

                                    if expandedGroups.contains(group.id) {
                                        if group.child.isEmpty {
                                            Text(" ")
                                                .padding(.leading, 40)
                                        } else {
                                            ForEach(group.child) { item in
                                                HStack {
                                                    // Item
                                                    Image(systemName: "app")
                                                    Text(item.name.isEmpty ? "New Item" : item.name)
                                                        .foregroundStyle(item.name.isEmpty ? .secondary : .primary)
                                                    Spacer()
                                                }
                                                .frame(height: rowHeight)
                                                .padding(.leading, 40)
                                                .swipeActions(edge: .trailing) {
                                                    Button(role: .destructive) {
                                                        deleteItem(item)
                                                    } label: {
                                                        Image(systemName: "trash")
                                                    }
                                                }
                                                .swipeActions(edge: .leading) {
                                                    Button {
                                                        copyItem(item)
                                                    } label: {
                                                        Image(systemName: "doc.on.doc")
                                                    }
                                                }
                                                .contentShape(Rectangle())
                                                .background(
                                                    GeometryReader { proxy in
                                                        Color.clear
                                                            .onAppear { itemFrames[item.id] = proxy.frame(in: .global) }
                                                            .onChange(of: proxy.frame(in: .global)) { newFrame in
                                                                itemFrames[item.id] = newFrame
                                                            }
                                                    }
                                                )
                                                .onTapGesture {
                                                    itemArrowEdge = arrowEdge(for: itemFrames[item.id])
                                                    editingItem = item
                                                }
                                                .popover(item: Binding(
                                                    get: { editingItem?.id == item.id ? editingItem : nil },
                                                    set: { editingItem = $0 }
                                                ), attachmentAnchor: .rect(.bounds), arrowEdge: itemArrowEdge) { item in
                                                    EditItemView(item: item)
                                                        .presentationCompactAdaptation(.none)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            //.navigationTitle("Titles")
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button {
                        //Info  addTitle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    Spacer()
                    Text("モチメモ")
                    Spacer()
                    Button {
                        addTitle()
                    } label: {
                        // ＋Title
                        Image(systemName: "bag.badge.plus")
                    }
                }
                .frame(height: rowHeight)
                .padding(.horizontal)
                .background(.thinMaterial)
            }
        }
    }

    private func addTitle() {
        let newTitle = M1Title(name: "")
        modelContext.insert(newTitle)
    }

    private func addGroup(to title: M1Title) {
        let newGroup = M2Group(name: "", parent: title)
        modelContext.insert(newGroup)
    }

    private func addItem(to group: M2Group) {
        let newItem = M3Item(name: "", parent: group)
        modelContext.insert(newItem)
    }

    private func toggleTitle(_ title: M1Title) {
        if expandedTitles.contains(title.id) {
            expandedTitles.remove(title.id)
        } else {
            expandedTitles.insert(title.id)
            if title.child.isEmpty {
                addGroup(to: title)
            }
        }
    }

    private func toggleGroup(_ group: M2Group) {
        if expandedGroups.contains(group.id) {
            expandedGroups.remove(group.id)
        } else {
            expandedGroups.insert(group.id)
            if group.child.isEmpty {
                addItem(to: group)
            }
        }
    }

    private func deleteTitle(_ title: M1Title) {
        // remove all groups and their items before deleting the title
        for group in title.child {
            deleteGroup(group)
        }
        modelContext.delete(title)
    }

    private func deleteGroup(_ group: M2Group) {
        // remove all items belonging to this group before deleting the group
        for item in group.child {
            modelContext.delete(item)
        }
        modelContext.delete(group)
    }

    private func deleteItem(_ item: M3Item) {
        // delete only the specified item
        modelContext.delete(item)
    }

    private func copyTitle(_ title: M1Title) {
        let newTitle = M1Title(name: title.name, note: title.note, createdAt: title.createdAt.addingTimeInterval(-0.001))
        modelContext.insert(newTitle)
        for group in title.child {
            copyGroup(group, to: newTitle)
        }
    }

    private func copyGroup(_ group: M2Group, to parent: M1Title? = nil) {
        let parentTitle = parent ?? group.parent
        guard let parentTitle = parentTitle else { return }
        let newGroup = M2Group(name: group.name, note: group.note, parent: parentTitle)
        modelContext.insert(newGroup)
        if parent != nil {
            parentTitle.child.append(newGroup)
        } else if let index = parentTitle.child.firstIndex(where: { $0.id == group.id }) {
            parentTitle.child.insert(newGroup, at: index + 1)
        } else {
            parentTitle.child.append(newGroup)
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
    }

    private func copyItem(_ item: M3Item, to parent: M2Group? = nil) {
        let parentGroup = parent ?? item.parent
        guard let parentGroup = parentGroup else { return }
        let newItem = M3Item(name: item.name, note: item.note, stock: item.stock, need: item.need, weight: item.weight, parent: parentGroup)
        modelContext.insert(newItem)
        if parent != nil {
            parentGroup.child.append(newItem)
        } else if let index = parentGroup.child.firstIndex(where: { $0.id == item.id }) {
            parentGroup.child.insert(newItem, at: index + 1)
        } else {
            parentGroup.child.append(newItem)
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

// 子ビュー（編集フォーム）
struct EditTitleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var title: M1Title   // ← これでプロパティにバインディングできる

    var body: some View {
        VStack {
            TextField("", text: $title.name, prompt: Text("New Title"))
            TextField("Note", text: $title.note)
            HStack {
                Spacer()
                Button("Done") {
                    try? context.save() // 必要なら保存
                    dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

struct EditGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var group: M2Group

    var body: some View {
        VStack {
            TextField("", text: $group.name, prompt: Text("New Group"))
            TextField("Note", text: $group.note)
            HStack {
                Spacer()
                Button("Done") {
                    try? context.save()
                    dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var item: M3Item

    var body: some View {
        VStack {
            TextField("", text: $item.name, prompt: Text("New Item"))
            TextField("Note", text: $item.note)
            Stepper("Stock: \(item.stock)", value: $item.stock)
            Stepper("Need: \(item.need)", value: $item.need)
            TextField("Weight", value: $item.weight, format: .number)
            HStack {
                Spacer()
                Button("Done") {
                    try? context.save()
                    dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}


#Preview {
    ContentView()
}

