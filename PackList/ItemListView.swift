import SwiftUI
import SwiftData

struct ItemListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let pack: M1Pack
    let initialGroup: M2Group

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sortedGroups) { group in
                    Section {
                        ForEach(group.child.sorted { $0.order < $1.order }) { item in
                            ItemRowView(item: item)
                        }
                        .onMove { source, destination in
                            moveItem(in: group, from: source, to: destination)
                        }
                    } header: {
                        GroupRowView(group: group, isHeader: true)
                    }
                    .id(group.id)
                    .environment(\.editMode, .constant(.active))
                    .padding(.horizontal, 0)
                    .background(COLOR_ROW_GROUP)
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .navigationTitle(pack.name.isEmpty ? "New Pack" : pack.name)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 0) {
                            Image(systemName: "chevron.backward")
                            Text("Group")
                        }
                    }
                }
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button(action: addItem) {
//                        Image(systemName: "plus.circle")
//                    }
//                }
            }
            .onAppear {
                proxy.scrollTo(initialGroup.id, anchor: .top)
            }
        }
    }

//    private func addItem() {
//        let newItem = M3Item(name: "", order: initialGroup.nextItemOrder(), parent: initialGroup)
//        modelContext.insert(newItem)
//        withAnimation {
//            initialGroup.child.append(newItem)
//            initialGroup.normalizeItemOrder()
//        }
//    }

    private func moveItem(in group: M2Group, from source: IndexSet, to destination: Int) {
        var items = group.child.sorted { $0.order < $1.order }
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.order = index
        }
        group.child = items
    }
}

#Preview {
    let pack = M1Pack(name: "", order: 0)
    let group = M2Group(name: "", order: 0, parent: pack)
    pack.child.append(group)
    return ItemListView(pack: pack, initialGroup: group)
}
