import SwiftUI
import SwiftData

struct GroupListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let pack: M1Pack

    private let rowHeight: CGFloat = 44
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var listID = UUID() // Listリフレッシュ用

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
                        .frame(width: 180)
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
        .id(listID)   // listIDが変わるとListが作り直される
        .padding(.horizontal, 0)
        .navigationTitle(pack.name.isEmpty ? "New Pack" : pack.name)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack {
                    Button {
                        try? modelContext.save() // Undoスタックがクリアされる
                        modelContext.undoManager?.removeAllActions()
                        dismiss()
                    } label: {
                        HStack(spacing: 0) {
                            Image(systemName: "chevron.backward")
                            //Text("Pack")
                        }
                    }
                    .padding(.trailing, 8)

                    Button {
                        withAnimation {
                            modelContext.undoManager?.undo()
                        }
                        listID = UUID()  // ここで List を再描画
                        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo)
                    
                    //    Button {
                    //        withAnimation {
                    //            modelContext.undoManager?.redo()
                    //        }
                    //        listID = UUID()  // ここで List を再描画
                    //        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                    //    } label: {
                    //        Image(systemName: "arrow.uturn.forward")
                    //    }
                    //    .disabled(!canRedo)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: addGroup) {
                    Image(systemName: "plus.rectangle")
                }
            }
        }
        .onAppear {
            try? modelContext.save() // Undoスタックがクリアされる
            modelContext.undoManager?.removeAllActions()
            updateUndoRedo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
            updateUndoRedo()
        }
    }

    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo
            canRedo = um.canRedo
        }
    }

    private func addGroup() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        let newGroup = M2Group(name: "", order: pack.nextGroupOrder(), parent: pack)
        modelContext.insert(newGroup)
        withAnimation {
            pack.child.append(newGroup)
            pack.normalizeGroupOrder()
        }
    }

    private func moveGroup(from source: IndexSet, to destination: Int) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

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
