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

    var body: some View {
        NavigationView {
            List {
                ForEach(titles) { title in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedTitles.contains(title.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedTitles.insert(title.id)
                                } else {
                                    expandedTitles.remove(title.id)
                                }
                            }
                        )
                    ) {
                        ForEach(title.child) { group in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedGroups.contains(group.id) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedGroups.insert(group.id)
                                        } else {
                                            expandedGroups.remove(group.id)
                                        }
                                    }
                                )
                            ) {
                                if group.child.isEmpty {
                                    Text(" ")
                                        .padding(.leading)
                                } else {
                                    ForEach(group.child) { item in
                                        Text(item.name)
                                            .padding(.leading)
                                    }
                                }
                            } label: {
                                Text(group.name)
                            }
                        }
                    } label: {
                        HStack {
                            Text(title.name)
                            Spacer()
                            Button {
                                editingTitle = title
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Titles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Title") {
                        addTitle()
                    }
                }
            }
        }
        .sheet(item: $editingTitle) { title in
            EditTitleView(title: title)            // バインディングは子で作る
        }
    }

    private func addTitle() {
        let newTitle = M1Title(name: "New Title")
        modelContext.insert(newTitle)
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
                TextField("Name", text: $title.name)
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


#Preview {
    ContentView()
}

