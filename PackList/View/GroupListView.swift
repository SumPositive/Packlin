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
                    EditGroupView(group: group) {
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


struct EditGroupView: View {
    @Bindable var group: M2Group
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var nameIsFocused: Bool
    
    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        VStack {
            HStack {    // Actions
                // チェックON/OFF
                Button {
                    // チェック・トグル；配下の全item.checkを反転する。.stockはそのまま
                    checkToggle()
                } label: {
                    VStack {
                        if allItemsChecked {
                            Image(systemName: "checkmark.rectangle")
                            Text("action.check.off")
                                .font(.caption)
                        }else{
                            Image(systemName: "rectangle")
                            Text("action.check.on")
                                .font(.caption)
                        }
                    }
                }
                .tint(.purple)
                .padding(.horizontal, 8)
                
                // 複製
                Button {
                    duplicateGroup()
                } label: {
                    VStack {
                        Image(systemName: "plus.square.on.square")
                        Text("action.duplicate")
                            .font(.caption)
                    }
                }
                .tint(.accentColor)
                .padding(.horizontal, 8)
                
                Spacer()

                // 削除
                Button {
                    // EditItemViewを閉じる
                    onClose()
                    // Itemを削除する
                    deleteGroup()
                } label: {
                    VStack {
                        Image(systemName: "trash")
                        Text("action.delete")
                            .font(.caption)
                    }
                }
                .tint(.red)
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 8)

            HStack {
                Text("edit.name")
                    .font(.caption)
                Spacer()
            }
            .padding(.bottom, -7)
            TextEditor(text: $group.name)
                .font(FONT_EDIT)
                .onChange(of: group.name) { newValue, oldValue in
                    // 最大文字数制限
                    if APP_MAX_NAME_LEN < newValue.count {
                        group.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                    }
                }
                .focused($nameIsFocused) // フォーカス状態とバインド
                .frame(height: 80)

            HStack {
                Text("edit.memo")
                    .font(.caption)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, -7)
            TextEditor(text: $group.memo)
                .font(FONT_EDIT)
                .onChange(of: group.memo) { newValue, oldValue in
                    // 最大文字数制限
                    if APP_MAX_MEMO_LEN < newValue.count {
                        group.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                    }
                }
                .frame(height: 80)
        }
        .padding(.horizontal, 8)
        .frame(width: 320, height: 280)
        .onAppear {
            // UndoGrouping
            modelContext.undoManager?.beginUndoGrouping()
            if group.name.isEmpty {
                nameIsFocused = true
            }
        }
        .onDisappear() {
            // 末尾のスペースと改行を除去
            group.name = group.name.trimTrailSpacesAndNewlines
            group.memo = group.memo.trimTrailSpacesAndNewlines
            // UndoGrouping
            if let um = modelContext.undoManager, 0 < um.groupingLevel {
                um.endUndoGrouping()
            }
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
    }

    /// チェック・トグル；配下の全item.checkを反転する。.stockはそのまま
    private func checkToggle() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
        
        let toggle = allItemsChecked
        let items = group.child
        for item in items {
            item.check = (!toggle && 0 < item.need)
        }
    }

    /// 現在のGroupを複製して現在行に追加する
    private func duplicateGroup() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
        
        guard let parent = group.parent else { return }
        let newGroup = M2Group(name: group.name, memo: group.memo,
                               order: parent.nextGroupOrder(),
                               parent: parent)
        modelContext.insert(newGroup)
        withAnimation {
            if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
                // 現在行の下に追加
                parent.child.insert(newGroup, at: index + 1)
            }
            parent.normalizeGroupOrder()
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
    }
    private func copyItem(_ item: M3Item, to parent: M2Group) {
        let newItem = M3Item(name: item.name, memo: item.memo,
                             stock: item.stock, need: item.need, weight: item.weight,
                             order: parent.nextItemOrder(), parent: parent)
        modelContext.insert(newItem)
        parent.child.append(newItem)
        parent.normalizeItemOrder()
    }

    /// 現在のGroupを削除する
    private func deleteGroup() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
        // groupの配下を削除
        for item in group.child {
            modelContext.delete(item)
        }
        // groupを削除：pack側から削除して整列する
        if let parent = group.parent,
           let index = parent.child.firstIndex(where: { $0.id == group.id }) {
            parent.child.remove(at: index)
            parent.normalizeGroupOrder()
        }
        modelContext.delete(group)
    }

}


#Preview {
    GroupListView(pack: M1Pack(name: "", order: 0))
}
