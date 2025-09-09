//
//  PackDetailView.swift
//  PackList
//
//  Created by ChatGPT on 2025/09/09.
//

import SwiftUI
import SwiftData

struct PackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let pack: M1Pack

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            ForEach(sortedGroups) { group in
                GroupRowView(group: group)
            }
            .onMove(perform: moveGroup)
            .environment(\.editMode, .constant(.active))
        }
        .listStyle(.plain)
        .navigationTitle(pack.name.isEmpty ? "New Pack" : pack.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addGroup()
                } label: {
                    Image(systemName: "plus.rectangle")
                }
            }
        }
    }

    private func addGroup() {
        let newGroup = M2Group(name: "", order: pack.nextGroupOrder(), parent: pack)
        modelContext.insert(newGroup)
        withAnimation {
            pack.child.append(newGroup)
            pack.normalizeGroupOrder()
        }
    }

    private func moveGroup(from source: IndexSet, to destination: Int) {
        var groups = sortedGroups
        groups.move(fromOffsets: source, toOffset: destination)
        for (index, group) in groups.enumerated() {
            group.order = index
        }
        pack.child = groups
    }
}

