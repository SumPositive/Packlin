//
//  ItemListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//

import SwiftUI
import SwiftData

struct ItemListView: View {
    let pack: M1Pack
    let group: M2Group

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    @AppStorage(AppStorageKey.footerMessage) private var footerMessage: Bool = true

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingGroup: M2Group?
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?

    /// DBからソートして取得する（group.child は.order昇順）
    private var sortedItems: [M3Item] {
        group.child.sorted { $0.order < $1.order }
    }

    // Popup表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingPopup: Bool { editingGroup != nil || editingItem != nil }

    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(sortedItems) { item in
                        NavigationLink(
                            value: AppDestination.itemEdit(
                                packID: pack.id,
                                groupID: group.id,
                                itemID: item.id,
                                sort: nil
                            )
                        ) {
                            ItemRowView(item: item) { selected, point in
                                editingItem = selected
                                popupAnchor = point
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(COLOR_ROW_BACK)
                    }
                    .onMove(perform: moveItem)
                } header: {
                    GroupRowView(group: group, isHeader: true) { selected, point in
                        editingGroup = selected
                        popupAnchor = point
                    }
                    .background(COLOR_ROW_GROUP)
                    //.padding(.top, -20) // 上余白を無くすため、GroupRowで＋20、ここでー20
                } footer: {
                    if footerMessage {
                        // フッター：操作説明、アイコン説明
                        FooterView()
                            .listRowSeparator(.hidden) // 下線なし
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
            .padding(.leading, 0)
            .padding(.trailing, 8)
            .navigationTitle(pack.name.placeholderText("placeholder.pack.new"))
            .navigationBarBackButtonHidden(true)
            .toolbar {
                navigationToolbar
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
            //----------------------------------
            //(ZStack 1) Popupで表示
            if let item = editingItem {
                PopupView(anchor: popupAnchor) {
                    //.onDismiss：PopupView内から閉じる場合
                    editingItem = nil
                    popupAnchor = nil
                } content: {
                    ItemQuickEditView(item: item)
                }
                .zIndex(1)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    if isShowingPopup {
                        guard abs(horizontal) > 80 || abs(vertical) > 80 else { return }
                        editingGroup = nil
                        editingItem = nil
                        popupAnchor = nil
                        return
                    }

                    guard horizontal > 80, abs(vertical) < 50 else { return }
                    dismiss()
                }
        )
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
                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    //Text("Group")
                }
            }
            .padding(.trailing, 8)
            .disabled(isShowingPopup)

            // Undo
            Button {
                canUndo = false
                modelContext.undoManager?.performUndo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
            }
            .disabled(!canUndo || isShowingPopup)
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            //EditButton()
            //    .disabled(isShowingPopup)
            //    .padding(.trailing, 8)

            // Redo
            Button {
                canRedo = false
                modelContext.undoManager?.performRedo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
            }
            .disabled(!canRedo || isShowingPopup)
            .padding(.trailing, 8)
            // アイテム追加ボタン
            Button(action: addItem) {
                Image(systemName: "plus.circle")
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    .padding(.trailing, 8)
            }
            .disabled(isShowingPopup)
        }
    }

    /// フッター：操作説明、アイコン説明
    struct FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("itemList.footer.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("itemList.footer.checkmark.circle")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.circle")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("itemList.footer.inStock")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("itemList.footer.outOfStock")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("itemList.footer.circle.fill")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            }
            .padding(.top, 20)
            .padding(.leading, 30)
            .padding(.trailing, 8)
        }
    }
    
    
    /// アイテム追加
    private func addItem() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        let newOrder: Int
        switch insertionPosition {
            case .head:
                let minOrder = group.child.map { $0.order }.min() ?? 0
                newOrder = minOrder - 1
            case .tail:
                let maxOrder = group.child.map { $0.order }.max() ?? -1
                newOrder = maxOrder + 1
        }
        
        let newItem = M3Item(name: "", order: newOrder, parent: group)
        modelContext.insert(newItem)
        withAnimation {
            switch insertionPosition {
                case .head:
                    group.child.insert(newItem, at: 0)
                case .tail:
                    group.child.append(newItem)
            }
            group.normalizeItemOrder()
        }
    }

    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo && modelContext.hasChanges // && 編集なければ非活性
            canRedo = um.canRedo
        } else {
            canUndo = false
            canRedo = false
        }
    }

    private func moveItem(from source: IndexSet, to destination: Int) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        var items = sortedItems
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.order = index
        }
        group.child = items
        // この後、sortedItemsが再取得される
    }
}


#Preview {
    let pack = M1Pack(name: "", order: 0)
    let group = M2Group(name: "", order: 0, parent: pack)
    pack.child.append(group)
    return ItemListView(pack: pack, group: group)
}
