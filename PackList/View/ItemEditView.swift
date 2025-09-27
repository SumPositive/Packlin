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

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: Field?
    @State private var canUndo = false
    @State private var canRedo = false
    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]
    @AppStorage("itemEdit.move.lastPackID") private var lastMovePackID: String = ""
    @AppStorage("itemEdit.move.lastGroupID") private var lastMoveGroupID: String = ""
    @State private var isShowingMoveSheet = false
    @State private var selectedPackID: String
    @State private var selectedGroupID: String
    @State private var keepSourceItem = false
    @State private var moveInsertPosition: MoveInsertPosition = .end
    @AppStorage("itemEdit.move.lastInsertPosition")
    private var lastMoveInsertPositionRawValue: String = MoveInsertPosition.end.rawValue
    @AppStorage("itemEdit.move.lastKeepOriginal")
    private var lastMoveKeepOriginal: Bool = false

    private let sectionCornerRadius: CGFloat = 12

    private var nameFieldMinHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .title2).lineHeight * 2 + 16
    }

    //private var sectionFieldBackground: Color { Color(.secondarySystemBackground) }
    //private var sectionButtonBackground: Color { Color(.systemBackground) }
    //private var sectionButtonBorder: Color { Color(.quaternarySystemFill) }

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
                return "item.move.position.start"
            case .end:
                return "item.move.position.end"
            }
        }
    }

    init(pack: M1Pack, group: M2Group, item: M3Item, onDismiss: @escaping () -> Void) {
        self.pack = pack
        self.group = group
        self._item = Bindable(item)
        self.onDismiss = onDismiss
        self._selectedPackID = State(initialValue: pack.id)
        self._selectedGroupID = State(initialValue: group.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                //    // 見出し
                //    VStack(alignment: .leading, spacing: 4) {
                //        // パック名 表示
                //        pack.name.placeholderText("placeholder.pack.new")
                //            .font(.caption)
                //            .foregroundStyle(.secondary)
                //        // グループ名 表示
                //        group.name.placeholderText("placeholder.group.new")
                //            .font(.headline)
                //    }
                // 操作
                EditorSection(title: "edit.actions") {
                    HStack(spacing: 12) {
                        // 移動
                        Button {
                            prepareMoveSheet()
                            isShowingMoveSheet = true
                        } label: {
                            Label("action.move", systemImage: "hand.point.up.left.and.text")
                                .frame(width: 90, height: 44)
                                .background(COLOR_BACK_INPUT)
                                .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                        .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel(Text("action.duplicate"))
                        
                        // 複写
                        Button {
                            duplicateItem()
                            onDismiss()
                        } label: {
                            Label("action.duplicate", systemImage: "plus.square.on.square")
                                .frame(width: 90, height: 44)
                                .background(COLOR_BACK_INPUT)
                                .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                        .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel(Text("action.duplicate"))
                        
                        // 右端へ
                        Spacer()
                        // 削除
                        Button(role: .destructive) {
                            deleteItem()
                            onDismiss()
                        } label: {
                            Label("action.delete", systemImage: "trash")
                                .frame(width: 84, height: 44)
                                .background(COLOR_BACK_INPUT)
                                .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                        .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel(Text("action.delete"))
                    }
                }
                // 名称
                EditorSection(title: "edit.name") {
                    TextField("", text: $item.name, prompt: Text("placeholder.item.new"), axis: .vertical)
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
                EditorSection(title: "edit.memo") {
                    TextEditor(text: $item.memo)
                        .font(FONT_EDIT)
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
                EditorSection(title: "item.section.quantity") {
                    // 数量 編集
                    ItemQuantityEditor(item: item)
                        //.background(COLOR_ROW_GROUP)
                        //.cornerRadius(8)
                        .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(COLOR_BACK_POPUP) // Color(.systemGroupedBackground))
        .navigationTitle(item.name.placeholderText("placeholder.item.new"))
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .padding(.trailing, 8)

                Button {
                    withAnimation {
                        modelContext.undoManager?.undo()
                    }
                    updateUndoRedo()
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
                    updateUndoRedo()
                    NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!canRedo)
                .padding(.trailing, 8)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    if horizontal > 80 && horizontal > vertical {
                        onDismiss()
                    }
                }
        )
        .onAppear {
            modelContext.undoManager?.beginUndoGrouping()
            updateUndoRedo()
            if item.name.isEmpty {
                focusedField = .name
            }
        }
        .onDisappear {
            item.name = item.name.trimTrailSpacesAndNewlines
            item.memo = item.memo.trimTrailSpacesAndNewlines
            if let undoManager = modelContext.undoManager, undoManager.groupingLevel > 0 {
                undoManager.endUndoGrouping()
            }
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
            updateUndoRedo()
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            ItemMoveSheetView(
                packs: sortedPacks,
                selectedPackID: $selectedPackID,
                selectedGroupID: $selectedGroupID,
                keepOriginal: $keepSourceItem,
                insertPosition: $moveInsertPosition,
                disableConfirm: selectedDestinationGroup == nil,
                onConfirm: handleMoveConfirmation,
                onCancel: { isShowingMoveSheet = false }
            )
        }
        .onChange(of: selectedPackID) { _, _ in
            guard isShowingMoveSheet else { return }
            syncGroupSelection(useStoredPreference: false)
        }
    }

    private func duplicateItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
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
                parent.child.insert(newItem, at: index + 1)
            }
            parent.normalizeItemOrder()
        }
    }

    private func deleteItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        if let group = item.parent,
           let index = group.child.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                group.child.remove(at: index)
                group.normalizeItemOrder()
            }
        }
        modelContext.delete(item)
    }

    private func updateUndoRedo() {
        if let undoManager = modelContext.undoManager {
            canUndo = undoManager.canUndo
            canRedo = undoManager.canRedo
        } else {
            canUndo = false
            canRedo = false
        }
    }

    private var sortedPacks: [M1Pack] {
        packs.sorted { $0.order < $1.order }
    }

    private var selectedPack: M1Pack? {
        sortedPacks.first(where: { $0.id == selectedPackID })
    }

    private var selectedDestinationGroup: M2Group? {
        guard let pack = selectedPack else { return nil }
        return pack.child.sorted { $0.order < $1.order }
            .first(where: { $0.id == selectedGroupID })
    }

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

    private func performMoveOrCopy(to destinationGroup: M2Group, copy: Bool) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        if !copy,
           let sourceGroup = item.parent {
            var sourceItems = sourceGroup.child.sorted { $0.order < $1.order }
            if let index = sourceItems.firstIndex(where: { $0.id == item.id }) {
                sourceItems.remove(at: index)
                sourceGroup.child = sourceItems
                sourceGroup.normalizeItemOrder()
            }
        }

        var destinationItems = destinationGroup.child.sorted { $0.order < $1.order }
        let insertIndex: Int
        switch moveInsertPosition {
        case .start:
            insertIndex = 0
        case .end:
            insertIndex = destinationItems.count
        }
        let clampedIndex = max(0, min(insertIndex, destinationItems.count))

        if copy {
            let newItem = M3Item(name: item.name,
                                 memo: item.memo,
                                 stock: item.stock,
                                 need: item.need,
                                 weight: item.weight,
                                 order: clampedIndex,
                                 parent: destinationGroup)
            modelContext.insert(newItem)
            destinationItems.insert(newItem, at: clampedIndex)
        } else {
            item.parent = destinationGroup
            destinationItems.insert(item, at: clampedIndex)
        }

        destinationGroup.child = destinationItems
        destinationGroup.normalizeItemOrder()
    }
}

/// Popup用の簡易編集ビュー（数量のみ）
struct ItemQuickEditView: View {
    @Bindable var item: M3Item

    @Environment(\.modelContext) private var modelContext

    init(item: M3Item) {
        self._item = Bindable(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // アイテム名称表示
            item.name.placeholderText("placeholder.item.new")
                .font(FONT_NAME)
                .foregroundStyle(item.name.isEmpty ? COLOR_NAME_EMPTY : COLOR_NAME)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            // 数量 編集
            ItemQuantityEditor(item: item)
        }
        .padding(8)
        .frame(width: 300)
        .onAppear {
            modelContext.undoManager?.beginUndoGrouping()
        }
        .onDisappear {
            if let undoManager = modelContext.undoManager, undoManager.groupingLevel > 0 {
                undoManager.endUndoGrouping()
            }
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
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
            FieldConfig(title: "item.field.weight", unit: "unit.gram",
                        maxValue: APP_MAX_WEIGHT_NUM, binding: weightBinding),
            // 在庫数
            FieldConfig(title: "item.field.stock", unit: "unit.piece",
                        maxValue: APP_MAX_STOCK_NUM, binding: stockBinding),
            // 必要数
            FieldConfig(title: "item.field.need", unit: "unit.piece",
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
            item.check = (0 < item.stock && item.need <= item.stock)
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
            item.check = (0 < item.stock && item.need <= item.stock)
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

/// アイテム移動 シート
private struct ItemMoveSheetView: View {
    let packs: [M1Pack]
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
                Section("item.move.destination") {
                    // 移動先のPack
                    Picker("item.move.destinationPack", selection: $selectedPackID) {
                        ForEach(sortedPacks, id: \.id) { pack in
                            pack.name.truncTail(20)
                                .placeholderText("placeholder.pack.new")
                                .tag(pack.id)
                        }
                    }
                    .pickerStyle(.menu)  // メニュー型

                    // 移動先のGroup
                    Picker("item.move.destinationGroup", selection: $selectedGroupID) {
                        ForEach(availableGroups, id: \.id) { group in
                            group.name.truncTail(20)
                                .placeholderText("placeholder.group.new")
                                .tag(group.id)
                        }
                    }
                    .pickerStyle(.menu)  // メニュー型
                    .disabled(availableGroups.isEmpty)

                    // 移動先は先頭か末尾か
                    Picker("item.move.position", selection: $insertPosition) {
                        ForEach(ItemEditView.MoveInsertPosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 移動元
                Section("item.move.original") {
                    // コピーを作成する
                    Toggle("item.move.keepOriginal", isOn: $keepOriginal)
                }
            }
            //.listSectionSpacing(.compact)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(keepOriginal ? "action.duplicate" : "action.move", action: onConfirm)
                        .disabled(disableConfirm)
                }
            }
        }
        .presentationDetents([.height(340), .fraction(1)])
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
        VStack(alignment: .leading, spacing: 6) {
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
