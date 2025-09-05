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

                            Text(title.name.isEmpty ? "New Title" : title.name)
                                .foregroundStyle(title.name.isEmpty ? .secondary : .primary)
                            Spacer()
                            Button {
                                addGroup(to: title)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingTitle = title }

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

                                        Text(group.name.isEmpty ? "New Group" : group.name)
                                            .foregroundStyle(group.name.isEmpty ? .secondary : .primary)
                                        Spacer()
                                        Button {
                                            addItem(to: group)
                                        } label: {
                                            Image(systemName: "plus")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                    .padding(.leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingGroup = group }

                                    if expandedGroups.contains(group.id) {
                                        if group.child.isEmpty {
                                            Text(" ")
                                                .padding(.leading, 40)
                                        } else {
                                            ForEach(group.child) { item in
                                                HStack {
                                                    Text(item.name.isEmpty ? "New Item" : item.name)
                                                        .foregroundStyle(item.name.isEmpty ? .secondary : .primary)
                                                    Spacer()
                                                }
                                                .padding(.leading, 40)
                                                .contentShape(Rectangle())
                                                .onTapGesture { editingItem = item }
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
                    Text("Titles")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addTitle()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editingTitle) { title in
            EditTitleView(title: title)            // バインディングは子で作る
        }
        .sheet(item: $editingGroup) { group in
            EditGroupView(group: group)
        }
        .sheet(item: $editingItem) { item in
            EditItemView(item: item)
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
        NavigationStack {
            Form {
                TextField("", text: $title.name, prompt: Text("New Title"))
                TextField("Note", text: $title.note)
            }
            .navigationTitle("Edit Title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save() // 必要なら保存
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EditGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var group: M2Group

    var body: some View {
        NavigationStack {
            Form {
                TextField("", text: $group.name, prompt: Text("New Group"))
                TextField("Note", text: $group.note)
            }
            .navigationTitle("Edit Group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Bindable var item: M3Item

    var body: some View {
        NavigationStack {
            Form {
                TextField("", text: $item.name, prompt: Text("New Item"))
                TextField("Note", text: $item.note)
                Stepper("Stock: \(item.stock)", value: $item.stock)
                Stepper("Need: \(item.need)", value: $item.need)
                TextField("Weight", value: $item.weight, format: .number)
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}


#Preview {
    ContentView()
}

