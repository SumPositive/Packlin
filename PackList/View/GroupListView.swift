//
//  GroupListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//

import SwiftUI
import SwiftData

struct GroupListView: View {
    let pack: M1Pack

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var listID = UUID() // Listリフレッシュ用
    @State private var editingGroup: M2Group?
    @State private var popupAnchor: CGPoint?

    private let rowHeight: CGFloat = 44

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }
    
    // Popup表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingPopup: Bool { editingGroup != nil }

    
    var body: some View {
        ZStack {
            List {
                ForEach(sortedGroups) { group in
                    ZStack {
                        GroupRowView(group: group, isHeader: false) { selected, point in
                            editingGroup = selected
                            popupAnchor = point
                        }

                        GeometryReader { geo in
                            HStack {
                                Spacer()
                                NavigationLink(value: AppDestination.itemList(packID: pack.id, groupID: group.id)) {
                                    Color.clear
                                }
                                .buttonStyle(.plain)
                                .frame(width: geo.size.width/2.0) // 画面右半分タップでナビ遷移
                                .contentShape(Rectangle()) //タップ領域
                                .background(Color.clear)
                                .padding(.trailing, 8)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .background(COLOR_ROW_GROUP)
                }
                .onMove(perform: moveGroup)
                .environment(\.editMode, .constant(.active))
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
            .id(listID)   // listIDが変わるとListが作り直される
            .padding(.horizontal, 0)
            .navigationTitle(pack.name.placeholderText("placeholder.pack.new"))
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(isShowingPopup)
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
                    .disabled(!canUndo || isShowingPopup)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation {
                            modelContext.undoManager?.redo()
                        }
                        listID = UUID()  // ここで List を再描画
                        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo || isShowingPopup)
                    .padding(.trailing, 8)

                    Button(action: addGroup) {
                        Image(systemName: "plus.rectangle")
                    }
                    .disabled(isShowingPopup)
                }
            }
            .onAppear {
                updateUndoRedo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }

            //----------------------------------
            //(ZStack 1) Popupで表示
            if let group = editingGroup {
                PopupView(anchor: popupAnchor) {
                    editingGroup = nil
                    popupAnchor = nil
                } content: {
                    GroupEditView(group: group) {
                        //.onClose：内から閉じる場合
                        editingGroup = nil
                        popupAnchor = nil
                    }
                }
                .zIndex(1)
            }
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
