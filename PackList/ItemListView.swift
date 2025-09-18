import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var itemFrames: [M3Item.ID: CGRect] = [:]

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
        let items = sortedItems(in: group)
        Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { enumeratedItem in
                itemRow(for: enumeratedItem.element,
                        in: group,
                        index: enumeratedItem.offset)
            }
            .onMove { source, destination in
                moveItem(in: group, from: source, to: destination)
            }
            if items.isEmpty {
                emptyDropTarget(for: group)
            }
        } header: {
            GroupRowView(group: group, isHeader: true) { selected, point in
                //editingGroup = selected
                //popupAnchor = point
            }
        }
        .id(group.id)
        .environment(\.editMode, .constant(.active))
        .padding(.horizontal, 0)
        .background(COLOR_ROW_GROUP)
    }

    private func itemRow(for item: M3Item, in group: M2Group, index: Int) -> some View {
        ItemRowView(item: item) { selected, point in
            editingItem = selected
            popupAnchor = point
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        registerFrame(geo: geo, for: item)
                    }
                    .onChange(of: geo.frame(in: .named("itemList"))) { _, _ in
                        registerFrame(geo: geo, for: item)
                    }
                    .onDisappear {
                        itemFrames.removeValue(forKey: item.id)
                    }
            }
        )
        .draggable(ItemDragData(itemID: item.id))
        .dropDestination(for: ItemDragData.self) { items, location in
            guard let payload = items.first else { return false }
            let baseIndex: Int
            if let frame = itemFrames[item.id] {
                baseIndex = index + (location.y >= frame.height / 2 ? 1 : 0)
            } else {
                baseIndex = index
            }
            let destinationIndex = dropInsertionIndex(for: payload.itemID,
                                                       in: group,
                                                       baseIndex: baseIndex)
            relocateItem(withID: payload.itemID,
                          to: group,
                          destinationIndex: destinationIndex)
            return true
        }
    }

    private func emptyDropTarget(for group: M2Group) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .dropDestination(for: ItemDragData.self) { items, _ in
                guard let payload = items.first else { return false }
                let destinationIndex = dropInsertionIndex(for: payload.itemID,
                                                           in: group,
                                                           baseIndex: 0)
                relocateItem(withID: payload.itemID,
                              to: group,
                              destinationIndex: destinationIndex)
                return true
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

    private func registerFrame(geo: GeometryProxy, for item: M3Item) {
        let frame = geo.frame(in: .named("itemList"))
        if itemFrames[item.id] != frame {
            itemFrames[item.id] = frame
        }
    }

    private func dropInsertionIndex(for itemID: M3Item.ID, in group: M2Group, baseIndex: Int) -> Int {
        let sourceGroup = pack.child.first { parentGroup in
            parentGroup.child.contains { $0.id == itemID }
        }

        var index = max(baseIndex, 0)
        if let sourceGroup,
           sourceGroup.id == group.id,
           let sourceIndex = sortedItems(in: sourceGroup).firstIndex(where: { $0.id == itemID }) {
            if sourceIndex < index {
                index -= 1
            }
            let upperBound = max(group.child.count - 1, 0)
            index = min(index, upperBound)
        } else {
            index = min(index, group.child.count)
        }
        return max(index, 0)
    }

    private func relocateItem(withID itemID: M3Item.ID, to destinationGroup: M2Group, destinationIndex: Int) {
        guard let sourceGroup = pack.child.first(where: { group in
            group.child.contains { $0.id == itemID }
        }),
        let removalIndex = sourceGroup.child.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        if sourceGroup.id == destinationGroup.id && destinationIndex == removalIndex {
            return
        }

        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        let item = sourceGroup.child[removalIndex]
        withAnimation {
            sourceGroup.child.remove(at: removalIndex)

            var destinationItems = destinationGroup.child
            let clampedIndex = max(0, min(destinationIndex, destinationItems.count))
            destinationItems.insert(item, at: clampedIndex)
            destinationGroup.child = destinationItems
            item.parent = destinationGroup

            if sourceGroup.id != destinationGroup.id {
                sourceGroup.normalizeItemOrder()
            }
            destinationGroup.normalizeItemOrder()
        }
    }

    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo
            canRedo = um.canRedo
        }
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

private struct ItemDragData: Transferable, Codable {
    let itemID: M3Item.ID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: ItemDragData.self, contentType: .packListItemData)
    }
}

private extension UTType {
    static let packListItemData = UTType(exportedAs: "com.sumpositive.packlist.item")
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
