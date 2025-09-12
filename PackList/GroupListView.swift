import SwiftUI
import SwiftData

struct GroupListView: View {
    @Environment(\.modelContext) private var modelContext
    let pack: M1Pack

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            ForEach(sortedGroups) { group in
                NavigationLink(destination: ItemListView(pack: pack, initialGroup: group)) {
                    GroupRowView(group: group)
                }
            }
            .onMove(perform: moveGroup)
            .environment(\.editMode, .constant(.active))
        }
        .listStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
        .padding(0)
        .navigationTitle(pack.name.isEmpty ? "New Pack" : pack.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addGroup) {
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

#Preview {
    GroupListView(pack: M1Pack(name: "", order: 0))
}
