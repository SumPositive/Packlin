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
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Button {
                                toggleTitleExpansion(title)
                            } label: {
                                Image(systemName: expandedTitles.contains(title.id) ? "chevron.down" : "chevron.right")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            Text(title.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingTitle = title
                        }

                        if expandedTitles.contains(title.id) {
                            ForEach(title.child) { group in
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Button {
                                            toggleGroupExpansion(group)
                                        } label: {
                                            Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        Text(group.name)
                                        Spacer()
                                    }
                                    .padding(.leading)

                                    if expandedGroups.contains(group.id) {
                                        if group.child.isEmpty {
                                            Text(" ")
                                                .padding(.leading, 32)
                                        } else {
                                            ForEach(group.child) { item in
                                                Text(item.name)
                                                    .padding(.leading, 32)
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

    private func toggleTitleExpansion(_ title: M1Title) {
        if expandedTitles.contains(title.id) {
            expandedTitles.remove(title.id)
        } else {
            expandedTitles.insert(title.id)
        }
    }

    private func toggleGroupExpansion(_ group: M2Group) {
        if expandedGroups.contains(group.id) {
            expandedGroups.remove(group.id)
        } else {
            expandedGroups.insert(group.id)
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

