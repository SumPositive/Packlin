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
            List(titles, selection: $selectedTitle) { title in
                Text(title.name)
            }
        } content: {
            if let selectedTitle {
                List(selectedTitle.child, selection: $selectedGroup) { group in
                    Text(group.name)
                }
            } else {
                Text("Select a title")
            }
        } detail: {
            if let selectedGroup {
                List(selectedGroup.child) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text("lack: \(item.lack)")
                    }
                }
            } else {
                Text("Select a group")
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: [Title.self, Group.self, Item.self],
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let title = Title(name: "Sample Title")
    let group = Group(name: "Sample Group", parent: title)
    title.child.append(group)
    group.child.append(Item(name: "Sample Item", stock: 1, need: 2, weight: 0.5, parent: group))
    context.insert(title)
    return ContentView()
        .modelContainer(container)
}
