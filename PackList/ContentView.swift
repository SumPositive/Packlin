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
    @Query private var titles: [Title]
    @State private var selectedTitle: Title?
    @State private var selectedGroup: Group?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTitle) {
                ForEach(titles) { title in
                    TitleRow(title: title)
                        .tag(title)
                }
                Button("New Title") {
                    let newTitle = Title(name: "", note: "")
                    modelContext.insert(newTitle)
                    try? modelContext.save()
                }
            }
        } content: {
            if let selectedTitle {
                List(selection: $selectedGroup) {
                    ForEach(selectedTitle.child) { group in
                        GroupRow(group: group)
                            .tag(group)
                    }
                    Button("New Group") {
                        let newGroup = Group(name: "", note: "", parent: selectedTitle)
                        modelContext.insert(newGroup)
                        try? modelContext.save()
                    }
                }
            } else {
                Text("Select a title")
            }
        } detail: {
            if let selectedGroup {
                List {
                    ForEach(selectedGroup.child) { item in
                        ItemRow(item: item)
                    }
                    Button("New Item") {
                        let newItem = Item(name: "", note: "", parent: selectedGroup)
                        modelContext.insert(newItem)
                        try? modelContext.save()
                    }
                }
            } else {
                Text("Select a group")
            }
        }
    }
}

struct TitleRow: View {
    @Bindable var title: Title

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $title.name)
            TextField("Note", text: $title.note)
        }
    }
}

struct GroupRow: View {
    @Bindable var group: Group

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $group.name)
            TextField("Note", text: $group.note)
        }
    }
}

struct ItemRow: View {
    @Bindable var item: Item

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $item.name)
            TextField("Note", text: $item.note)
        }
    }
}

#Preview {
    ContentView()
}

