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
    @Query(sort: [SortDescriptor(\Title.createdAt, order: .reverse)]) private var titles: [Title]
    @State private var expandedTitles: Set<PersistentIdentifier> = []

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
                            Text(group.name)
                                .padding(.leading)
                        }
                    } label: {
                        Text(title.name)
                    }
                }
                Button("Add Title") {
                    addTitle()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listStyle(.plain)
            .navigationTitle("Titles")
        }
    }

    private func addTitle() {
        let newTitle = Title(name: "New Title")
        modelContext.insert(newTitle)
    }
}

#Preview {
    ContentView()
}

