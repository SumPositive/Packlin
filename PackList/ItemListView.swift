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

    @State private var canUndo = false
    @State private var canRedo = false

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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        modelContext.undoManager?.undo()
                        updateUndoRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo)

                    Button {
                        modelContext.undoManager?.redo()
                        updateUndoRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo)
                }
            }
            .onAppear {
                proxy.scrollTo(initialGroup.id, anchor: .top)
                updateUndoRedo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }
        }
    }

    private func updateUndoRedo() {
        let manager = modelContext.undoManager
        canUndo = manager?.canUndo ?? false
        canRedo = manager?.canRedo ?? false
    }

    private func moveItem(in group: M2Group, from source: IndexSet, to destination: Int) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

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
