import SwiftUI
import SwiftData

struct ItemListView: View {
    @Environment(\.modelContext) private var modelContext
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
        .navigationTitle(group.name.isEmpty ? "New Group" : group.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addItem) {
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
    ItemListView(group: M2Group(name: "", order: 0))
}
