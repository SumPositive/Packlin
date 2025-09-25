//
//  ItemListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//
//　Item移動がGroupを超えて可能にするためListでなくLazyVStackを利用、そのため
//　RowのswipeActionsが使えなくなるので、ItemEditView上にActionsボタンを表示することにした
//

import SwiftUI
import SwiftData

struct ItemListView: View {
    let pack: M1Pack
    let initialGroup: M2Group
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var listID = UUID() // Listリフレッシュ用
    @State private var editingGroup: M2Group?
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?
    
    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }
    
    // Popup表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingPopup: Bool { editingGroup != nil || editingItem != nil }
    
    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                groupList(proxy: proxy)
                    .onAppear {
                        DispatchQueue.main.async {
                            // メインスレッドでList描画後に実行する
                            proxy.scrollTo(initialGroup.id, anchor: .top)
                        }
                        guard editingItem == nil else {
                            updateUndoRedo()
                            return
                        }
                        // ここでは、modelContext.save()しない
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                        updateUndoRedo()
                    }
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
            //----------------------------------
            //(ZStack 1) Popupで表示
            if let item = editingItem {
                PopupView(anchor: popupAnchor) {
                    //.onDismiss：PopupView内から閉じる場合
                    editingItem = nil
                    popupAnchor = nil
                } content: {
                    ItemEditView(item: item) {
                        //.onClose：EditItemView内から閉じる場合
                        editingItem = nil
                        popupAnchor = nil
                    }
                }
                .zIndex(1)
            }
        }
        .coordinateSpace(name: "itemList")
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard horizontal > 80, abs(vertical) < 50 else { return }

                    if isShowingPopup {
                        editingGroup = nil
                        editingItem = nil
                        popupAnchor = nil
                    } else {
                        dismiss()
                    }
                }
        )
    }
    
    @ViewBuilder
    private func groupList(proxy: ScrollViewProxy) -> some View {
        // List → ScrollView + LazyVStack(pinnedViews) に変更（セクションヘッダをピン留め）
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sortedGroups) { group in
                    groupSection(group)
                }
            }
        }
        .id(listID)   // listIDが変わるとListが作り直される（ScrollViewでも同様に再構築トリガとして使用）
        .navigationTitle(pack.name.placeholderText("placeholder.pack.new"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            navigationToolbar
        }
    }
    
    @ViewBuilder
    private func groupSection(_ group: M2Group) -> some View {
        Section {
            ForEach(sortedItems(in: group)) { item in
                ItemRowView(item: item) { selected, point in
                    editingItem = selected
                    popupAnchor = point
                }
                .contentShape(Rectangle()) // D&D の当たり判定を広げる
                // 一次元方式：どのセクションにもドロップ可能にするため、行をドラッグ可能に
                .draggable("\(item.id)") // ペイロード・トークンは item.id を文字列化したもの
                // この行の「直後」に挿入
                .dropDestination(for: String.self) { tokens, _ in
                    guard let token = tokens.first else { return false }
                    moveItemByDrag(token, toGroup: group, target: item, placement: .after)
                    listID = UUID()  // ここで List を再描画（ScrollViewでも再構築）
                    return true
                }
            }
            
            // セクション末尾の受け口（末尾へ挿入）
            Color.clear
                .frame(height: 12)
                .dropDestination(for: String.self) { tokens, _ in
                    guard let token = tokens.first else { return false }
                    moveItemByDrag(token, toGroup: group, target: nil, placement: .after) // nil:末尾へ
                    listID = UUID()  // ここで List を再描画
                    return true
                }
        } header: {
            GroupRowView(group: group, isHeader: true) { selected, point in
                editingGroup = selected
                popupAnchor = point
            }
            .background(COLOR_ROW_GROUP)
            .contentShape(Rectangle())
            // ヘッダーにドロップ → 先頭に挿入
            .dropDestination(for: String.self) { tokens, _ in
                guard let token = tokens.first else { return false }
                let firstItem = sortedItems(in: group).first
                moveItemByDrag(token, toGroup: group, target: firstItem, placement: .before)
                listID = UUID()  // ここで List を再描画
                return true
            }
        }
        .id(group.id)
        .padding(.horizontal, 0)
        .background(COLOR_ROW_GROUP)
        .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
    }
    
    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button(action: {
                dismiss()
                // GroupListView.onAppearで.save()が呼ばれる
            }) {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.backward")
                    //Text("Group")
                }
            }
            .padding(.trailing, 8)
            .disabled(isShowingPopup)
            
            // Undo
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
            // Redo
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
        }
        
    }
    
    private func sortedItems(in group: M2Group) -> [M3Item] {
        group.child.sorted { $0.order < $1.order }
    }
    
    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo
            canRedo = um.canRedo
        }
    }
    

    // ===== 一次元方式：ドラッグ&ドロップ移動（グループ跨ぎ） =====
    
    // ドラッグペイロード（id が UUID でない場合は適宜変更）
    private func dragToken(for item: M3Item) -> String { "\(item.id)" }
    
    // トークンから (元グループ, アイテム, 元index) を解決
    private func findItem(byToken token: String) -> (M2Group, M3Item, Int)? {
        for g in pack.child.sorted(by: { $0.order < $1.order }) {
            let items = sortedItems(in: g)
            if let idx = items.firstIndex(where: { dragToken(for: $0) == token }) {
                return (g, items[idx], idx)
            }
        }
        return nil
    }
    
    private enum DropPlacement {
        case before
        case after
    }

    // グループ跨ぎ移動の本体：targetItem の直前/直後（nilなら先頭/末尾）に挿入
    private func moveItemByDrag(_ token: String,
                                toGroup targetGroup: M2Group,
                                target targetItem: M3Item?,
                                placement: DropPlacement) {
        guard let (sourceGroup, movingItem, srcIndex) = findItem(byToken: token) else { return }

        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }
        
        // 1) 元グループから取り外し（order を詰める）
        var srcItems = sortedItems(in: sourceGroup)
        guard srcIndex < srcItems.count else { return }
        _ = srcItems.remove(at: srcIndex)
        sourceGroup.child = srcItems
        sourceGroup.normalizeItemOrder()
        
        // 2) 先グループの挿入位置
        var dstItems = sortedItems(in: targetGroup)
        var insertIndex = dstItems.count

        if sourceGroup.id == targetGroup.id,
           let targetItem,
           targetItem.id == movingItem.id {
            insertIndex = min(srcIndex, dstItems.count)
        } else {
            switch placement {
            case .before:
                if let targetItem,
                   let idx = dstItems.firstIndex(where: { $0.id == targetItem.id }) {
                    insertIndex = idx
                } else {
                    insertIndex = 0
                }
            case .after:
                if let targetItem,
                   let idx = dstItems.firstIndex(where: { $0.id == targetItem.id }) {
                    insertIndex = idx + 1
                } else {
                    insertIndex = dstItems.count
                }
            }
        }

        insertIndex = max(0, min(insertIndex, dstItems.count))

        // 3) 挿入して親の付け替え
        movingItem.parent = targetGroup
        dstItems.insert(movingItem, at: insertIndex)
        targetGroup.child = dstItems
        targetGroup.normalizeItemOrder()
    }
}


#Preview {
    let pack = M1Pack(name: "", order: 0)
    let group = M2Group(name: "", order: 0, parent: pack)
    pack.child.append(group)
    return ItemListView(pack: pack, initialGroup: group)
}

