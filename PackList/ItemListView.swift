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
                PopupView(
                    anchor: popupAnchor,
                    onDismiss: {
                        editingItem = nil
                        popupAnchor = nil
                    }
                ) {
                    EditItemView(item: item)
                }
                .zIndex(1)
            }
        }
        .coordinateSpace(name: "itemList")
    }

    @ViewBuilder
    private func groupList(proxy: ScrollViewProxy) -> some View {
        List {
            ForEach(sortedGroups) { group in
                groupSection(group)
            }
        }
        .listStyle(.plain)
        .id(listID)   // listIDが変わるとListが作り直される
        .listSectionSpacing(0)
        .navigationTitle(pack.name.isEmpty ? "New Pack" : pack.name)
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
                .draggable(item.id)
                .dropDestination(for: M3Item.ID.self) { itemIDs, _ in
                    guard let itemID = itemIDs.first, itemID != item.id else {
                        return false
                    }
                    guard let targetIndex = sortedItems(in: group).firstIndex(where: { $0.id == item.id }) else {
                        return false
                    }
                    return relocateItem(withID: itemID, to: group, destinationIndex: targetIndex)
                }
            }
            .onMove { source, destination in
                moveItem(in: group, from: source, to: destination)
            }
        } header: {
            GroupRowView(group: group, isHeader: true) { selected, point in
                //editingGroup = selected
                //popupAnchor = point
            }
            .dropDestination(for: M3Item.ID.self) { itemIDs, _ in
                guard let itemID = itemIDs.first else {
                    return false
                }
                return relocateItem(withID: itemID, to: group, destinationIndex: 0)
            }
        }
        .id(group.id)
        .environment(\.editMode, .constant(.active))
        .padding(.horizontal, 0)
        .background(COLOR_ROW_GROUP)
        .dropDestination(for: M3Item.ID.self) { itemIDs, _ in
            guard let itemID = itemIDs.first else {
                return false
            }
            return relocateItem(withID: itemID, to: group, destinationIndex: sortedItems(in: group).count)
        }
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

    private func moveItem(in group: M2Group, from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else {
            return
        }
        let items = sortedItems(in: group)
        guard items.indices.contains(sourceIndex) else {
            return
        }
        _ = relocateItem(withID: items[sourceIndex].id, to: group, destinationIndex: destination)
    }

    private func relocateItem(withID itemID: M3Item.ID, to targetGroup: M2Group, destinationIndex rawDestination: Int) -> Bool {
        guard let item = item(withID: itemID), let sourceGroup = item.parent else {
            return false
        }

        if sourceGroup.id == targetGroup.id {
            var destination = rawDestination
            let items = sortedItems(in: sourceGroup)
            guard let currentIndex = items.firstIndex(where: { $0.id == itemID }) else {
                return false
            }

            if currentIndex < destination {
                destination -= 1
            }

            let maxIndex = max(items.count - 1, 0)
            destination = max(0, min(destination, maxIndex))

            if destination == currentIndex {
                return false
            }

            performItemMove(item, to: targetGroup, destinationIndex: destination)
            return true
        } else {
            let destination = max(0, min(rawDestination, sortedItems(in: targetGroup).count))
            performItemMove(item, to: targetGroup, destinationIndex: destination)
            return true
        }
    }

    private func performItemMove(_ item: M3Item, to targetGroup: M2Group, destinationIndex: Int) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        relocate(item: item, to: targetGroup, destinationIndex: destinationIndex)
    }

    private func relocate(item: M3Item, to targetGroup: M2Group, destinationIndex: Int) {
        guard let sourceGroup = item.parent else {
            return
        }

        if sourceGroup.id == targetGroup.id {
            var items = sortedItems(in: sourceGroup)
            guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else {
                return
            }

            let movingItem = items.remove(at: currentIndex)
            let boundedDestination = max(0, min(destinationIndex, items.count))
            items.insert(movingItem, at: boundedDestination)
            sourceGroup.child = items
            movingItem.parent = sourceGroup
            sourceGroup.normalizeItemOrder()
        } else {
            var sourceItems = sortedItems(in: sourceGroup)
            guard let currentIndex = sourceItems.firstIndex(where: { $0.id == item.id }) else {
                return
            }
            let movingItem = sourceItems.remove(at: currentIndex)
            sourceGroup.child = sourceItems
            sourceGroup.normalizeItemOrder()

            var targetItems = sortedItems(in: targetGroup)
            let boundedDestination = max(0, min(destinationIndex, targetItems.count))
            targetItems.insert(movingItem, at: boundedDestination)
            targetGroup.child = targetItems
            movingItem.parent = targetGroup
            targetGroup.normalizeItemOrder()
        }
    }

    private func item(withID id: M3Item.ID) -> M3Item? {
        for group in pack.child {
            if let found = group.child.first(where: { $0.id == id }) {
                return found
            }
        }
        return nil
    }
}


/// Item 編集
/// 外枠 frameを固定サイズにして、内側をレイアウトしている
struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: M3Item
    @FocusState private var nameIsFocused: Bool
    
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
            HStack {
                Text("名称")
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
                Text("メモ")
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
                Text("個重量")
                    .font(.caption)
                TextField("", value: weightBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                Text("ｇ")
                    .font(.caption)
                Stepper("", value: weightBinding, in: 0...APP_MAX_WEIGHT_NUM)
                    .labelsHidden()
            }
            HStack {
                Text("在庫数")
                    .font(.caption)
                TextField("", value: stockBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                Text("個")
                    .font(.caption)
                Stepper("", value: stockBinding, in: 0...APP_MAX_STOCK_NUM)
                    .labelsHidden()
            }
            HStack {
                Text("必要数")
                    .font(.caption)
                TextField("", value: needBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                Text("個")
                    .font(.caption)
                Stepper("", value: needBinding, in: 0...APP_MAX_NEED_NUM)
                    .labelsHidden()
            }        }
        .padding(.horizontal, 16)
        .frame(width: 300, height: 280)
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
}


#Preview {
    let pack = M1Pack(name: "", order: 0)
    let group = M2Group(name: "", order: 0, parent: pack)
    pack.child.append(group)
    return ItemListView(pack: pack, initialGroup: group)
}
