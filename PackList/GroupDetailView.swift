//
//  GroupDetailView.swift
//  PackList
//
//  Created by ChatGPT on 2025/09/09.
//

import SwiftUI
import SwiftData

struct GroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let group: M2Group

    private var sortedItems: [M3Item] {
        group.child.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            ForEach(sortedItems) { item in
                ItemRowView(item: item)
            }
            .onMove(perform: moveItem)
            .environment(\.editMode, .constant(.active))
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .navigationTitle(group.name.isEmpty ? "New Group" : group.name)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }

                    Button {
                        // UnDo
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(true)
                    .padding(.horizontal, 30)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addItem()
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
    }

    private func addItem() {
        let newItem = M3Item(name: "", order: group.nextItemOrder(), parent: group)
        modelContext.insert(newItem)
        withAnimation {
            group.child.append(newItem)
            group.normalizeItemOrder()
        }
    }

    private func moveItem(from source: IndexSet, to destination: Int) {
        var items = sortedItems
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.order = index
        }
        group.child = items
    }
}

#Preview {
    GroupDetailView(group: M2Group(name: "", order: 0))
}
