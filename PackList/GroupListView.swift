import SwiftUI
import SwiftData

struct GroupListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let pack: M1Pack

    private let rowHeight: CGFloat = 44

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            ForEach(sortedGroups) { group in
                ZStack {
                    GroupRowView(group: group, isHeader: false)

                    HStack {
                        Spacer()
                        NavigationLink(destination: ItemListView(pack: pack, initialGroup: group)) {
                            Color.clear
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .frame(width: 80)
                        .padding(.trailing, 8)
                        .background(Color.clear).contentShape(Rectangle()) //タップ領域
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .background(COLOR_ROW_GROUP)
            }
            .onMove(perform: moveGroup)
            .environment(\.editMode, .constant(.active))
        }
        .listStyle(.plain)
        .padding(.horizontal, 0)
        .navigationTitle(pack.name.isEmpty ? "New Pack" : pack.name)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 0) {
                        Image(systemName: "chevron.backward")
                        Text("Pack")
                    }
                }
            }
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
