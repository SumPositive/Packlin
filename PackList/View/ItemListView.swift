//
//  ItemListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//
//　Item移動がGroupを超えて可能にするためListでなくLazyVStackを利用、そのため
//　RowのswipeActionsが使えなくなるので、EditItemView上にActionsボタンを表示することにした
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
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?
    
    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }
    
    // Popup表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingPopup: Bool { editingItem != nil }
    
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
            if let item = editingItem {
                PopupView(anchor: popupAnchor) {
                    //.onDismiss：PopupView内から閉じる場合
                    editingItem = nil
                    popupAnchor = nil
                } content: {
                    EditItemView(item: item) {
                        //.onClose：EditItemView内から閉じる場合
                        editingItem = nil
                        popupAnchor = nil
                    }
                }
                .zIndex(1)
            }
        }
        .coordinateSpace(name: "itemList")
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
                // この行の「直前」に挿入
                .dropDestination(for: String.self) { tokens, _ in
                    guard let token = tokens.first else { return false }
                    moveItemByDrag(token, toGroup: group, before: item)
                    listID = UUID()  // ここで List を再描画（ScrollViewでも再構築）
                    return true
                }
            }
            
            // セクション末尾の受け口（末尾へ挿入）
            Color.clear
                .frame(height: 12)
                .dropDestination(for: String.self) { tokens, _ in
                    guard let token = tokens.first else { return false }
                    moveItemByDrag(token, toGroup: group, before: nil)
                    listID = UUID()  // ここで List を再描画
                    return true
                }
        } header: {
            GroupRowView(group: group, isHeader: true) { selected, point in
                //editingGroup = selected
                //popupAnchor = point
            }
            .background(COLOR_ROW_GROUP)
            .contentShape(Rectangle())
            // ヘッダーにドロップ → 先頭に挿入
            .dropDestination(for: String.self) { tokens, _ in
                guard let token = tokens.first else { return false }
                moveItemByDrag(token, toGroup: group, before: nil) // nil:先頭へ
                listID = UUID()  // ここで List を再描画
                return true
            }
        }
        .id(group.id)
        .padding(.horizontal, 0)
        .background(COLOR_ROW_GROUP)
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
    
    // グループ跨ぎ移動の本体：targetItem の直後（nilなら末尾）に挿入
    private func moveItemByDrag(_ token: String,
                                toGroup targetGroup: M2Group,
                                before targetItem: M3Item?) {
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
        var insertIndex = dstItems.endIndex
        if let targetItem,
           var idx = dstItems.firstIndex(where: { $0.id == targetItem.id }) {
            idx += 1 // 直後へ挿入
            if idx < insertIndex {
                insertIndex = idx
            }
            // Safty
            insertIndex = max(0, min(insertIndex, dstItems.count))
        }else{
            // 先頭に挿入
            insertIndex = 0
        }
        
        // 3) 挿入して親の付け替え
        movingItem.parent = targetGroup
        dstItems.insert(movingItem, at: insertIndex)
        targetGroup.child = dstItems
        targetGroup.normalizeItemOrder()
    }
}


/// Item 編集
/// 外枠 frameを固定サイズにして、内側をレイアウトしている
struct EditItemView: View {
    @Bindable var item: M3Item
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var nameIsFocused: Bool

    private var gramUnit: String { String(localized: "unit.gram") }
    private var pieceUnit: String { String(localized: "unit.piece") }

    private var weightBinding: Binding<Int> {
        Binding(get: { item.weight },
                set: {
            // 入力制約
            let value = max(0, $0)
            if APP_MAX_WEIGHT_NUM < value {
                item.weight = APP_MAX_WEIGHT_NUM
            } else {
                item.weight = value
            }
        })
    }
    private var stockBinding: Binding<Int> {
        Binding(get: { item.stock },
                set: {
            // 入力制約
            let value = max(0, $0)
            if APP_MAX_STOCK_NUM < value {
                item.stock = APP_MAX_STOCK_NUM
            } else {
                item.stock = value
            }
        })
    }
    private var needBinding: Binding<Int> {
        Binding(get: { item.need },
                set: {
            // 入力制約
            let value = max(0, $0)
            if APP_MAX_NEED_NUM < value {
                item.need = APP_MAX_NEED_NUM
            } else {
                item.need = value
            }
        })
    }
    
    var body: some View {
        VStack {
            HStack {    // Actions
                Button {
                    duplicateItem()
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
                Text("Item.edit.title").font(.footnote)
                Spacer()

                Button {
                    // EditItemViewを閉じる
                    onClose()
                    // Itemを削除する
                    deleteItem()
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
                    .padding(4)
                TextEditor(text: $item.name)
                    .onChange(of: item.name) { newValue, oldValue in
                        // 最大文字数制限
                        if APP_MAX_NAME_LEN < newValue.count {
                            item.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                        }
                    }
                    .focused($nameIsFocused) // フォーカス状態とバインド
                    .frame(height: 60)
            }
            HStack {
                Text("edit.memo")
                    .font(.caption)
                    .padding(4)
                TextEditor(text: $item.memo)
                    .onChange(of: item.memo) { newValue, oldValue in
                        // 最大文字数制限
                        if APP_MAX_MEMO_LEN < newValue.count {
                            item.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                        }
                    }
                    .frame(height: 60)
            }
            .padding(.bottom, 8)

            HStack {
                Text("item.field.weight")
                    .font(.caption)
                TextField("", value: weightBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                Text(verbatim: gramUnit)
                    .font(.caption)
                Stepper("", value: weightBinding, in: 0...APP_MAX_WEIGHT_NUM)
                    .labelsHidden()
            }
            HStack {
                Text("item.field.stock")
                    .font(.caption)
                TextField("", value: stockBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                Text(verbatim: pieceUnit)
                    .font(.caption)
                Stepper("", value: stockBinding, in: 0...APP_MAX_STOCK_NUM)
                    .labelsHidden()
            }
            HStack {
                Text("item.field.need")
                    .font(.caption)
                TextField("", value: needBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                Text(verbatim: pieceUnit)
                    .font(.caption)
                Stepper("", value: needBinding, in: 0...APP_MAX_NEED_NUM)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 300, height: 320)
        .onAppear {
            // UndoGrouping
            modelContext.undoManager?.beginUndoGrouping()
            if item.name.isEmpty {
                nameIsFocused = true
            }
        }
        .onDisappear() {
            // 末尾のスペースと改行を除去
            item.name = item.name.trimTrailSpacesAndNewlines
            item.memo = item.memo.trimTrailSpacesAndNewlines
            // UndoGrouping
            if let um = modelContext.undoManager, 0 < um.groupingLevel {
                um.endUndoGrouping()
            }
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
    }

    /// 現在のItemを複製して現在行に追加する
    private func duplicateItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
        
        guard let parent = item.parent else { return }
        let newItem = M3Item(name: item.name, memo: item.memo,
                             stock: item.stock, need: item.need, weight: item.weight,
                             order: item.order,
                             parent: parent)
        modelContext.insert(newItem)
        withAnimation {
            if let index = parent.child.firstIndex(where: { $0.id == item.id }) {
                // 現在行の下に追加
                parent.child.insert(newItem, at: index + 1)
            }
            parent.normalizeItemOrder()
        }
    }
    
    /// 現在のItemを削除する
    private func deleteItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
        // itemを削除：group側から削除して整列する
        if let group = item.parent,
           let index = group.child.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                group.child.remove(at: index)
                group.normalizeItemOrder()
            }
        }
        modelContext.delete(item)
    }
    
}


#Preview {
    let pack = M1Pack(name: "", order: 0)
    let group = M2Group(name: "", order: 0, parent: pack)
    pack.child.append(group)
    return ItemListView(pack: pack, initialGroup: group)
}

