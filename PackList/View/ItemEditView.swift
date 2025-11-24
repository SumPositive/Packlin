//
//  ItemEditView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//

import SwiftUI
import SwiftData
import UIKit

/// 画面遷移用のアイテム編集ビュー
struct ItemEditView: View {
    let pack: M1Pack
    let group: M2Group
    @Bindable var item: M3Item
    let onDismiss: () -> Void
    let onSelectItem: (M3Item) -> Void
    let adjacentItemProvider: ((M3Item, Int) -> M3Item?)?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var history: UndoStackService

    @FocusState private var focusedField: Field?
    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]
    // PackListViewと同じ表示モードを共有し、初心者向け説明の表示を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    // 不揮発保存
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock
    // 不揮発保存：itemEdit.move用
    @AppStorage("itemEdit.move.lastPackID") private var lastMovePackID: String = ""
    @AppStorage("itemEdit.move.lastGroupID") private var lastMoveGroupID: String = ""
    @AppStorage("itemEdit.move.lastInsertPosition") private var lastMoveInsertPositionRawValue: String = MoveInsertPosition.end.rawValue
    @AppStorage("itemEdit.move.lastKeepOriginal") private var lastMoveKeepOriginal: Bool = false

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var isShowingMoveSheet = false
    @State private var selectedPackID: String
    @State private var selectedGroupID: String
    @State private var keepSourceItem = false
    @State private var moveInsertPosition: MoveInsertPosition = .end

    private let sectionCornerRadius: CGFloat = 12
    private let baseHeaderHeight: CGFloat = 44
    // 初心者モードでは説明テキストを差し込むので高さを可変にする
    private var headerHeight: CGFloat { isBeginnerMode ? 88 : baseHeaderHeight }
    private var isBeginnerMode: Bool { displayMode == .beginner }

    private var nameFieldMinHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .title2).lineHeight * 2 + 16
    }

    private var canSelectPreviousItem: Bool {
        adjacentItem(offset: -1) != nil
    }

    private var canSelectNextItem: Bool {
        adjacentItem(offset: 1) != nil
    }
    
    private enum Field: Hashable {
        case name
        case memo
    }

    enum MoveInsertPosition: String, CaseIterable, Identifiable {
        case start
        case end

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .start:
                return "グループの先頭"
            case .end:
                return "グループの末尾"
            }
        }
    }

    init(pack: M1Pack,
         group: M2Group,
         item: M3Item,
         onDismiss: @escaping () -> Void,
         onSelectItem: @escaping (M3Item) -> Void,
         adjacentItemProvider: ((M3Item, Int) -> M3Item?)? = nil) {
        self.pack = pack
        self.group = group
        self._item = Bindable(item)
        self.onDismiss = onDismiss
        self.onSelectItem = onSelectItem
        self.adjacentItemProvider = adjacentItemProvider
        self._selectedPackID = State(initialValue: pack.id)
        self._selectedGroupID = State(initialValue: group.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                //    // 見出し
                //    VStack(alignment: .leading, spacing: 4) {
                //        // パック名 表示
                //        pack.name.placeholderText("新しいパック")
                //            .font(.caption)
                //            .foregroundStyle(.secondary)
                //        // グループ名 表示
                //        group.name.placeholderText("新しいグループ")
                //            .font(.headline)
                //    }
                // 操作
                EditorSection(title: "操作") {
                    VStack {
                        HStack(spacing: 20) {
                            // 上・前へ
                            Button {
                                // (-1) 1つ前のアイテムを編集対象に切り替える
                                selectAdjacentItem(by: -1)
                            } label: {
                                Label("前へ", systemImage: "arrow.up.circle")
                                    .frame(width: 90, height: 44)
                                    .background(COLOR_BACK_INPUT)
                                    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                            .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel(Text("前へ"))
                            .disabled(!canSelectPreviousItem)
                            
                            // 複製
                            Button {
                                item.duplicate()
                                onDismiss()
                            } label: {
                                Label("複製", systemImage: "plus.square.on.square")
                                    .frame(width: 90, height: 44)
                                    .background(COLOR_BACK_INPUT)
                                    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                            .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel(Text("複製"))
                            
                            Spacer()
                            // 削除
                            Button(role: .destructive) {
                                item.delete()
                                onDismiss()
                            } label: {
                                Label("削除", systemImage: "trash")
                                    .frame(width: 90, height: 44)
                                    .background(COLOR_BACK_INPUT)
                                    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                            .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel(Text("削除"))
                        }
                        // 2段目
                        HStack(spacing: 20) {
                            // 下・次へ
                            Button {
                                // (+1) 1つ次のアイテムを編集対象に切り替える
                                selectAdjacentItem(by: 1)
                            } label: {
                                Label("次へ", systemImage: "arrow.down.circle")
                                    .frame(width: 90, height: 44)
                                    .background(COLOR_BACK_INPUT)
                                    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                            .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel(Text("次へ"))
                            .disabled(!canSelectNextItem)

                            // 移動
                            Button {
                                prepareMoveSheet()
                                isShowingMoveSheet = true
                            } label: {
                                Label("移動", systemImage: "hand.point.up.left.and.text")
                                    .frame(width: 90, height: 44)
                                    .background(COLOR_BACK_INPUT)
                                    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                            .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel(Text("移動"))

                            Spacer()
                            // 消す
                            Button(role: .destructive) {
                                // アイテムを初期値にリセット
                                resetItemToInitialState()
                            } label: {
                                Label("消す", systemImage: "eraser")
                                    .frame(width: 90, height: 44)
                                    .background(COLOR_BACK_INPUT)
                                    .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                            .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                    )
                            }
                            .accentColor(Color(.systemPink))
                            .accessibilityLabel(Text("消す"))
                        }
                    }
                }
                // 名称
                EditorSection(title: "名称") {
                    TextField("", text: $item.name, prompt: Text("新しいアイテム"), axis: .vertical)
                        .font(FONT_EDIT)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(6)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(minHeight: nameFieldMinHeight, alignment: .top)
                        .background(COLOR_BACK_INPUT)
                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                        .onChange(of: item.name) { newValue, _ in
                            if APP_MAX_NAME_LEN < newValue.count {
                                item.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                            }
                        }
                }
                // メモ
                EditorSection(title: "メモ") {
                    TextEditor(text: $item.memo)
                        .font(FONT_MEMO)
                        .focused($focusedField, equals: .memo)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(COLOR_BACK_INPUT)
                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                        .onChange(of: item.memo) { newValue, _ in
                            if APP_MAX_MEMO_LEN < newValue.count {
                                item.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                            }
                        }
                }

                // 数量
                EditorSection {
                    // 数量
                    Text("数量")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 0) {
                        // アイテム・アイコン・チェック
                        Button {
                            item.check.toggle()
                            if item.check {
                                if linkCheckWithStock {
                                    // チェックと在庫数を連動させる
                                    item.stock = item.need
                                }
                            }else{
                                if linkCheckWithStock {
                                    // チェックと在庫数を連動させる
                                    item.stock = 0
                                }
                            }
                        } label: {
                            Image(systemName
                                  : item.check ? "checkmark.circle"     // Check ON
                                  : item.need == 0 ? "circle.fill"      // Need = 0
                                  : item.need <= item.stock ? "circle.circle"
                                  : "circle")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .padding(8)

                        // 数量 編集
                        ItemQuantityEditor(item: item)
                            //.padding(.leading, 0)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(COLOR_ROW_GROUP)
        //.navigationTitle("アイテム編集")
        .navigationBarBackButtonHidden(true)
        //.navigationBarTitleDisplayMode(.inline)
        //.toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            // 編集画面でもPackListView風のヘッダーを共通化
            HStack(spacing: 0) {
                // 戻る＋説明
                VStack(spacing: 6) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)

                    if isBeginnerMode {
                        Text("アイテムヘッダー.説明.戻る")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 76)
                .padding(.horizontal, 6)

                // Undo＋説明
                VStack(spacing: 6) {
                    Button {
                        canUndo = false
                        modelContext.undoManager?.performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .imageScale(.small)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canUndo)

                    if isBeginnerMode {
                        Text("アイテムヘッダー.説明.Undo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 76)
                .padding(.horizontal, 6)

                Spacer(minLength: 0)

                Text(pack.name.placeholder("新しいパック"))
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Redo＋説明
                VStack(spacing: 6) {
                    Button {
                        canRedo = false
                        modelContext.undoManager?.performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .imageScale(.small)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canRedo)

                    if isBeginnerMode {
                        Text("アイテムヘッダー.説明.Redo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 76)
                .padding(.horizontal, 6)

                // 追加＋説明
                VStack(spacing: 6) {
                    Button {
                        addItemEdit()
                    } label: {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)

                    if isBeginnerMode {
                        Text("アイテムヘッダー.説明.アイテム追加")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 92)
                .padding(.horizontal, 6)
            }
            .tint(.primary)
            .frame(height: headerHeight)
            .padding(.horizontal, 8)
            .background(.thinMaterial)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    if !(horizontal <= 80 || abs(vertical) >= abs(horizontal)) {
                        // 右へ大きくスワイプしたときに閉じる
                        onDismiss()
                    }
                    else if vertical < -20, abs(horizontal) < abs(vertical) {
                        // 下へスワイプ時、キーボードを隠す
                        dismissKeyboard()
                    }
                }
        )
        .onAppear {
            // Undo grouping BEGIN
            modelContext.undoManager?.groupingBegin()
            if item.name.isEmpty {
                focusedField = .name
            }
        }
        .onDisappear {
            // Trim
            item.name = item.name.trimTrailSpacesAndNewlines
            item.memo = item.memo.trimTrailSpacesAndNewlines
            // チェックと在庫数を連動させる
            if linkCheckWithStock {
                item.check = (0 < item.need && item.need <= item.stock)
            }
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
            updateUndoRedo()
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            // 移動 設定シート
            ItemMoveSheetView(
                packs: sortedPacks,
                itemName: item.name,
                selectedPackID: $selectedPackID,
                selectedGroupID: $selectedGroupID,
                keepOriginal: $keepSourceItem,
                insertPosition: $moveInsertPosition,
                disableConfirm: selectedDestinationGroup == nil,
                onConfirm: handleMoveConfirmation,
                onCancel: { isShowingMoveSheet = false }
            )
            .presentationDetents([.height(400)]) // シートの高さ
        }
        .onChange(of: selectedPackID) { _, _ in
            guard isShowingMoveSheet else { return }
            syncGroupSelection(useStoredPreference: false)
        }
    }

    /// アイテム追加し、そのアイテムを編集状態にする
    private func addItemEdit() {
        // 履歴サービスを利用して新規追加を1つのアクションとして記録する
        history.perform(context: modelContext) {
            let items = group.child.sorted { $0.order < $1.order }
            let insertionIndex: Int = {
                switch insertionPosition {
                    case .head:
                        return 0
                    case .tail:
                        return items.count
                }
            }()
            
            let newOrder = sparseOrderForInsertion(items: items, index: insertionIndex) {
                // order のみを整え、child 配列を並べ替えない
                normalizeSparseOrders(items)
            }
            // 新しいアイテム
            let newItem = M3Item(name: "",
                                 order: newOrder,
                                 parent: group)
            // DB追加
            modelContext.insert(newItem)
            // ReOrder 不要
            
            // 新しいアイテムを編集対象にする
            withAnimation {
                onSelectItem(newItem)
            }
        }
    }
    
    /// 現在のアイテムを初期値にリセットする
    private func resetItemToInitialState() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        // 初期値をセット
        item.name = ""
        item.memo = ""
        item.check = false
        item.stock = 0
        item.need = 1
        item.weight = 0
        // フォーカスを.nameへ
        //focusedField = .name
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
    /// order順のPackリストを返す
    private var sortedPacks: [M1Pack] {
        packs.sorted { $0.order < $1.order }
    }
    /// selectedPackIDのPackを返す
    private var selectedPack: M1Pack? {
        sortedPacks.first(where: { $0.id == selectedPackID })
    }

    private var selectedDestinationGroup: M2Group? {
        guard let pack = selectedPack else { return nil }
        return pack.child.sorted { $0.order < $1.order }
            .first(where: { $0.id == selectedGroupID })
    }

    /// 移動　シート
    private func prepareMoveSheet() {
        keepSourceItem = lastMoveKeepOriginal
        if let storedInsertPosition = MoveInsertPosition(rawValue: lastMoveInsertPositionRawValue) {
            moveInsertPosition = storedInsertPosition
        } else {
            moveInsertPosition = .end
        }

        if let storedPack = sortedPacks.first(where: { $0.id == lastMovePackID }) {
            selectedPackID = storedPack.id
        } else if sortedPacks.contains(where: { $0.id == pack.id }) {
            selectedPackID = pack.id
        } else if let firstPack = sortedPacks.first {
            selectedPackID = firstPack.id
        } else {
            selectedPackID = ""
        }

        syncGroupSelection(useStoredPreference: true)
    }

    private func syncGroupSelection(useStoredPreference: Bool) {
        guard let pack = selectedPack else {
            selectedGroupID = ""
            return
        }

        let groups = pack.child.sorted { $0.order < $1.order }

        if useStoredPreference,
           let storedGroup = groups.first(where: { $0.id == lastMoveGroupID }) {
            selectedGroupID = storedGroup.id
            return
        }

        if let currentSelection = groups.first(where: { $0.id == selectedGroupID }) {
            selectedGroupID = currentSelection.id
            return
        }

        if pack.id == group.parent?.id,
           let currentGroup = groups.first(where: { $0.id == group.id }) {
            selectedGroupID = currentGroup.id
            return
        }

        if let firstGroup = groups.first {
            selectedGroupID = firstGroup.id
        } else {
            selectedGroupID = ""
        }
    }

    private func handleMoveConfirmation() {
        guard let destinationGroup = selectedDestinationGroup else { return }

        performMoveOrCopy(to: destinationGroup, copy: keepSourceItem)
        lastMovePackID = selectedPackID
        lastMoveGroupID = destinationGroup.id
        lastMoveInsertPositionRawValue = moveInsertPosition.rawValue
        lastMoveKeepOriginal = keepSourceItem
        isShowingMoveSheet = false
        onDismiss()
    }
    /// 移動 or 複写を実行する
    private func performMoveOrCopy(to destinationGroup: M2Group, copy: Bool) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        // 移動時も order のみを真実とするため、sourceGroup.child には触れない

        let destinationItems = destinationGroup.child.sorted { $0.order < $1.order }
        let insertIndex: Int
        switch moveInsertPosition {
        case .start:
            insertIndex = 0
        case .end:
            insertIndex = destinationItems.count
        }
        let clampedIndex = max(0, min(insertIndex, destinationItems.count))

        let newOrder = sparseOrderForInsertion(items: destinationItems, index: clampedIndex) {
            // child を再代入せずに order のみ補正する
            normalizeSparseOrders(destinationItems)
        }

        if copy {
            let newItem = M3Item(name: item.name,
                                 memo: item.memo,
                                 stock: item.stock,
                                 need: item.need,
                                 weight: item.weight,
                                 order: newOrder,
                                 parent: destinationGroup)
            modelContext.insert(newItem)
        } else {
            item.parent = destinationGroup
            item.order = newOrder
        }
    }

    /// 編集対象のアイテムを選択する（前へ、次へ）
    /// - Parameter offset: 移動量 (-1)1つ前へ　(+1)1つ次へ
    private func selectAdjacentItem(by offset: Int) {
        guard let target = adjacentItem(offset: offset) else { return }
        withAnimation {
            onSelectItem(target)
        }
    }
    /// 前後のアイテムを取得する
    /// - Parameter offset: 移動量 (-1)1つ前のアイテム　(+1)1つ次のアイテム
    private func adjacentItem(offset: Int) -> M3Item? {
        if let provider = adjacentItemProvider {
            return provider(item, offset)
        }

        guard offset != 0,
              let parent = item.parent else { return nil }

        let orderedItems = parent.child.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }

        guard let currentIndex = orderedItems.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }

        let destinationIndex = currentIndex + offset
        guard orderedItems.indices.contains(destinationIndex) else {
            return nil
        }

        return orderedItems[destinationIndex]
    }
    
    /// キーボードを隠す
    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
}

/// Popup用の簡易編集ビュー（数量のみ）
struct ItemQuickEditView: View {
    @Bindable var item: M3Item

    @Environment(\.modelContext) private var modelContext
    // 不揮発保存：チェックと在庫数を連動させる
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock

    init(item: M3Item) {
        self._item = Bindable(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // アイテム名称表示
            item.name.placeholderText("新しいアイテム")
                .font(FONT_NAME)
                .foregroundStyle(item.name.isEmpty ? COLOR_NAME_EMPTY : COLOR_NAME)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
            // 数量 編集
            ItemQuantityEditor(item: item)
        }
        .padding(8)
        .frame(width: 300)
        .onAppear {
            // Undo grouping BEGIN
            modelContext.undoManager?.groupingBegin()
        }
        .onDisappear {
            // チェックと在庫数を連動させる
            if linkCheckWithStock {
                item.check = (0 < item.need && item.need <= item.stock)
            }
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
    }
}

// 数量 編集
private struct ItemQuantityEditor: View {
    @Bindable var item: M3Item

    init(item: M3Item) {
        self._item = Bindable(item)
    }

    private struct FieldConfig {
        let title: LocalizedStringKey
        let unit: LocalizedStringKey
        let maxValue: Int
        let binding: Binding<Int>
    }

    private var fields: [FieldConfig] {
        [
            // 個重量
            FieldConfig(title: "個重量", unit: "g",
                        maxValue: APP_MAX_WEIGHT_NUM, binding: weightBinding),
            // 在庫数
            FieldConfig(title: "在庫数", unit: "個",
                        maxValue: APP_MAX_STOCK_NUM, binding: stockBinding),
            // 必要数
            FieldConfig(title: "必要数", unit: "個",
                        maxValue: APP_MAX_NEED_NUM, binding: needBinding)
        ]
    }

    private var weightBinding: Binding<Int> {
        Binding(get: { item.weight }, set: { newValue in
            let value = max(0, newValue)
            if APP_MAX_WEIGHT_NUM < value {
                item.weight = APP_MAX_WEIGHT_NUM
            } else {
                item.weight = value
            }
        })
    }

    private var stockBinding: Binding<Int> {
        Binding(get: { item.stock }, set: { newValue in
            let value = max(0, newValue)
            if APP_MAX_STOCK_NUM < value {
                item.stock = APP_MAX_STOCK_NUM
            } else {
                item.stock = value
            }
            //連動しない item.check = (0 < item.stock && item.need <= item.stock)
        })
    }

    private var needBinding: Binding<Int> {
        Binding(get: { item.need }, set: { newValue in
            let value = max(0, newValue)
            if APP_MAX_NEED_NUM < value {
                item.need = APP_MAX_NEED_NUM
            } else {
                item.need = value
            }
            //連動しない item.check = (0 < item.stock && item.need <= item.stock)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .center, spacing: 0) {
                    // 見出し
                    Text(field.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60)
                    // 数値入力
                    numberField(for: field, width: 75)
                    // 単位
                    Text(field.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                    // ステッパー
                    Stepper("", value: field.binding, in: 0...field.maxValue)
                        .labelsHidden()
                }
            }
        }
        .padding(8)
    }

    private func numberField(for field: FieldConfig, width: CGFloat) -> some View {
        TextField("", value: field.binding, format: .number)
            .font(FONT_EDIT)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(COLOR_BACK_INPUT)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// アイテム移動 設定シート
private struct ItemMoveSheetView: View {
    let packs: [M1Pack]
    let itemName: String
    @Binding var selectedPackID: String
    @Binding var selectedGroupID: String
    @Binding var keepOriginal: Bool
    @Binding var insertPosition: ItemEditView.MoveInsertPosition
    let disableConfirm: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var sortedPacks: [M1Pack] {
        packs.sorted { $0.order < $1.order }
    }

    private var selectedPack: M1Pack? {
        sortedPacks.first(where: { $0.id == selectedPackID })
    }

    private var availableGroups: [M2Group] {
        guard let pack = selectedPack else { return [] }
        return pack.child.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 移動先
                Section("移動先") {
                    // 移動先のPack
                    Picker(selection: $selectedPackID) {
                        ForEach(sortedPacks, id: \.id) { pack in
                            pack.name.truncTail(20)
                                .placeholderText("新しいパック")
                                .tag(pack.id)
                        }
                    } label: {
                        Label("", systemImage: "case")
                            .foregroundStyle(.secondary) // ← ここで色を変更
                    }
                    .pickerStyle(.menu)  // メニュー型

                    
                    // 移動先のGroup
                    Picker(selection: $selectedGroupID) {
                        ForEach(availableGroups, id: \.id) { group in
                            group.name.truncTail(20)
                                .placeholderText("新しいグループ")
                                .tag(group.id)
                        }
                    } label: {
                        Label("", systemImage: "square")
                            .foregroundStyle(.secondary) // ← ここで色を変更
                    }
                    .pickerStyle(.menu)  // メニュー型
                    .disabled(availableGroups.isEmpty)

                    // 移動先は先頭か末尾か
                    Picker("挿入位置", selection: $insertPosition) {
                        ForEach(ItemEditView.MoveInsertPosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 移動元
                Section("移動元") {
                    // コピーを作成する
                    Toggle("コピーを作成する（複製）", isOn: $keepOriginal)
                }
            }
            //.listSectionSpacing(.compact)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // 閉じる
                        //dismiss()
                        onCancel()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 移動 or 複写
                    Button(keepOriginal ? "複製する" : "移動する", action: onConfirm)
                        .disabled(disableConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .padding(.horizontal, 16)
                }
            }
            .navigationTitle(itemName.placeholder("新しいアイテム"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct EditorSection<Content: View>: View {
    private let title: LocalizedStringKey?
    private let content: Content

    init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}
