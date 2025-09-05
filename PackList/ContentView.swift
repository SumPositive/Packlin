//
//  ContentView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\M1Title.createdAt, order: .reverse)]) private var titles: [M1Title]
    @State private var expandedTitles: Set<PersistentIdentifier> = []
    @State private var expandedGroups: Set<PersistentIdentifier> = []
    @State private var editingTitle: M1Title?
    @State private var editingGroup: M2Group?
    @State private var editingItem: M3Item?
    private let rowHeight: CGFloat = 44

    var body: some View {
        NavigationView {
            List {
                ForEach(titles) { title in
                    VStack(alignment: .leading, spacing: 0) {
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
                        .contentShape(Rectangle())
                        .onTapGesture { editingTitle = title }
                        .popover(item: Binding(
                            get: { editingTitle?.id == title.id ? editingTitle : nil },
                            set: { editingTitle = $0 }
                        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) { title in
                            EditTitleView(title: title)
                                .presentationCompactAdaptation(.none)
                        }

                        if expandedTitles.contains(title.id) {
                            ForEach(title.child) { group in
                                VStack(alignment: .leading, spacing: 0) {
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
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingGroup = group }
                                    .popover(item: Binding(
                                        get: { editingGroup?.id == group.id ? editingGroup : nil },
                                        set: { editingGroup = $0 }
                                    ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) { group in
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
                                                .contentShape(Rectangle())
                                                .onTapGesture { editingItem = item }
                                                .popover(item: Binding(
                                                    get: { editingItem?.id == item.id ? editingItem : nil },
                                                    set: { editingItem = $0 }
                                                ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) { item in
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        //Info  addTitle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addTitle()
                    } label: {
                        // ＋Title
                        Image(systemName: "bag.badge.plus")
                    }
                }
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

