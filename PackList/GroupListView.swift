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
    
    var body: some View {
        ZStack {
            List {
                ForEach(sortedGroups) { group in
                    ZStack {
                        GroupRowView(group: group, isHeader: false) { selected, point in
                            editingGroup = selected
                            popupAnchor = point
                        }

                        HStack {
                            Spacer()
                            NavigationLink(value: AppDestination.itemList(packID: pack.id, groupID: group.id)) {
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
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        // PackViewに戻るときに保存
                        if let um = modelContext.undoManager, 0 < um.groupingLevel {
                            do {
                                try modelContext.save() // Undoスタックがクリアされる
                            } catch {
                                print("DB保存に失敗.2: \(error)")
                            }
                            um.removeAllActions()
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
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
                    .disabled(!canRedo)
                    .padding(.trailing, 8)

                    Button(action: addGroup) {
                        Image(systemName: "plus.rectangle")
                    }
                }
            }
            .onAppear {
                // PackViewから来たときとItemViewから戻ったときに保存
                if let um = modelContext.undoManager, 0 < um.groupingLevel {
                    do {
                        try modelContext.save() // Undoスタックがクリアされる
                    } catch {
                        print("DB保存に失敗.1: \(error)")
                    }
                    um.removeAllActions()
                }
                updateUndoRedo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }

            //----------------------------------
            //(ZStack 1) Popupで表示
            if let group = editingGroup {
                PopupView(
                    anchor: popupAnchor,
                    onDismiss: {
                        editingGroup = nil
                        popupAnchor = nil
                    }
                ) {
                    EditGroupView(group: group)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var group: M2Group
    @FocusState private var nameIsFocused: Bool
    
    var body: some View {
        VStack {
            HStack {
                Text("名称")
                    .font(.caption)
                TextEditor(text: $group.name)
                    .onChange(of: group.name) { newValue, oldValue in
                        // 最大文字数制限
                        if APP_MAX_NAME_LEN < newValue.count {
                            group.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                        }
                    }
                    .focused($nameIsFocused) // フォーカス状態とバインド
                    .frame(height: 60)
            }
            HStack {
                Text("メモ")
                    .font(.caption)
                TextEditor(text: $group.memo)
                    .onChange(of: group.memo) { newValue, oldValue in
                        // 最大文字数制限
                        if APP_MAX_MEMO_LEN < newValue.count {
                            group.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                        }
                    }
                    .frame(height: 60)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 300, height: 150)
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
}


#Preview {
    GroupListView(pack: M1Pack(name: "", order: 0))
}
