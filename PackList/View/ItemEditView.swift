//
//  ItemEditView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//

import SwiftUI
import SwiftData

/// 画面遷移用のアイテム編集ビュー
struct ItemEditView: View {
    let pack: M1Pack
    let group: M2Group
    @Bindable var item: M3Item
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case memo
    }

    init(pack: M1Pack, group: M2Group, item: M3Item, onDismiss: @escaping () -> Void) {
        self.pack = pack
        self.group = group
        self._item = Bindable(item)
        self.onDismiss = onDismiss
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    pack.name.placeholderText("placeholder.pack.new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    group.name.placeholderText("placeholder.group.new")
                        .font(.headline)
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("edit.name")) {
                TextField("", text: $item.name, prompt: Text("placeholder.item.new"))
                    .font(FONT_EDIT)
                    .focused($focusedField, equals: .name)
                    .textInputAutocapitalization(.sentences)
                    .onChange(of: item.name) { newValue, _ in
                        if APP_MAX_NAME_LEN < newValue.count {
                            item.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                        }
                    }
            }

            Section(header: Text("edit.memo")) {
                TextEditor(text: $item.memo)
                    .font(FONT_EDIT)
                    .focused($focusedField, equals: .memo)
                    .frame(minHeight: 120)
                    .onChange(of: item.memo) { newValue, _ in
                        if APP_MAX_MEMO_LEN < newValue.count {
                            item.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                        }
                    }
            }

            Section {
                ItemQuantityEditor(item: item, layout: .form)
            }

            Section {
                Button {
                    duplicateItem()
                } label: {
                    Label("action.duplicate", systemImage: "plus.square.on.square")
                }

                Button(role: .destructive) {
                    deleteItem()
                } label: {
                    Label("action.delete", systemImage: "trash")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(item.name.placeholderText("placeholder.item.new"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            modelContext.undoManager?.beginUndoGrouping()
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
    }

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
                parent.child.insert(newItem, at: index + 1)
            }
            parent.normalizeItemOrder()
        }
    }

    private func deleteItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
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
        onDismiss()
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
        VStack(alignment: .leading, spacing: 16) {
            item.name.placeholderText("placeholder.item.new")
                .font(FONT_NAME)
                .foregroundStyle(item.name.isEmpty ? COLOR_NAME_EMPTY : COLOR_NAME)
                .lineLimit(2)

            ItemQuantityEditor(item: item, layout: .popup)
        }
        .padding(16)
        .frame(width: 320)
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

private struct ItemQuantityEditor: View {
    enum Layout {
        case popup
        case form
    }

    @Bindable var item: M3Item
    let layout: Layout

    init(item: M3Item, layout: Layout) {
        self._item = Bindable(item)
        self.layout = layout
    }

    private struct FieldConfig {
        let title: LocalizedStringKey
        let unit: LocalizedStringKey
        let maxValue: Int
        let binding: Binding<Int>
    }

    private var fields: [FieldConfig] {
        [
            FieldConfig(title: "item.field.weight", unit: "unit.gram", maxValue: APP_MAX_WEIGHT_NUM, binding: weightBinding),
            FieldConfig(title: "item.field.stock", unit: "unit.piece", maxValue: APP_MAX_STOCK_NUM, binding: stockBinding),
            FieldConfig(title: "item.field.need", unit: "unit.piece", maxValue: APP_MAX_NEED_NUM, binding: needBinding)
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
        switch layout {
        case .popup:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    popupField(field)
                }
            }
        case .form:
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                    if 0 < index {
                        Divider()
                            .padding(.vertical, 8)
                    }
                    formField(field)
                }
            }
        }
    }

    @ViewBuilder
    private func popupField(_ field: FieldConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 12) {
                TextField("", value: field.binding, format: .number)
                    .font(FONT_EDIT)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(field.unit)
                    .font(.caption)
                Spacer()
                Stepper("", value: field.binding, in: 0...field.maxValue)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func formField(_ field: FieldConfig) -> some View {
        LabeledContent {
            HStack(spacing: 12) {
                TextField("", value: field.binding, format: .number)
                    .font(FONT_EDIT)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 80)
                Text(field.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("", value: field.binding, in: 0...field.maxValue)
                    .labelsHidden()
            }
        } label: {
            Text(field.title)
        }
    }
}
