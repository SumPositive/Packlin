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

    private let sectionCornerRadius: CGFloat = 12

    private var nameFieldMinHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .title2).lineHeight * 2 + 16
    }

    private var sectionFieldBackground: Color { Color(.secondarySystemBackground) }
    private var sectionButtonBackground: Color { Color(.systemBackground) }
    private var sectionButtonBorder: Color { Color(.quaternarySystemFill) }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    pack.name.placeholderText("placeholder.pack.new")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    group.name.placeholderText("placeholder.group.new")
                        .font(.headline)
                }

                EditorSection(title: "edit.name") {
                    TextField("", text: $item.name, prompt: Text("placeholder.item.new"), axis: .vertical)
                        .font(FONT_EDIT)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(6)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(minHeight: nameFieldMinHeight, alignment: .top)
                        .background(sectionFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                        .onChange(of: item.name) { newValue, _ in
                            if APP_MAX_NAME_LEN < newValue.count {
                                item.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                            }
                        }
                }

                EditorSection(title: "edit.memo") {
                    TextEditor(text: $item.memo)
                        .font(FONT_EDIT)
                        .focused($focusedField, equals: .memo)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .background(sectionFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                        .onChange(of: item.memo) { newValue, _ in
                            if APP_MAX_MEMO_LEN < newValue.count {
                                item.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                            }
                        }
                }

                EditorSection(title: "item.section.quantity") {
                    ItemQuantityEditor(item: item, layout: .form)
                }

                EditorSection(title: "edit.actions") {
                    HStack(spacing: 12) {
                        Button {
                            duplicateItem()
                        } label: {
                            Label("action.duplicate", systemImage: "plus.square.on.square")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .background(sectionButtonBackground)
                                .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                        .strokeBorder(sectionButtonBorder, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel(Text("action.duplicate"))

                        Button(role: .destructive) {
                            deleteItem()
                        } label: {
                            Label("action.delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .background(sectionButtonBackground)
                                .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                        .strokeBorder(sectionButtonBorder, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel(Text("action.delete"))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
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

                Button {
                    duplicateItem()
                } label: {
                    Image(systemName: "plus.rectangle")
                }
                .accessibilityLabel(Text("action.duplicate"))
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
        onDismiss()
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
            item.name.placeholderText("placeholder.item.new")
                .font(FONT_NAME)
                .foregroundStyle(item.name.isEmpty ? COLOR_NAME_EMPTY : COLOR_NAME)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            ItemQuantityEditor(item: item, layout: .popup)
        }
        .padding(12)
        .frame(width: 280)
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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .center, spacing: 8) {
                            numberField(for: field, width: 68)
                            Text(field.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Stepper("", value: field.binding, in: 0...field.maxValue)
                                .labelsHidden()
                        }
                    }
                }
            }
        case .form:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    HStack(alignment: .center, spacing: 12) {
                        Text(field.title)
                            .font(.subheadline)
                            .frame(minWidth: 110, alignment: .leading)
                        Spacer()
                        HStack(alignment: .center, spacing: 8) {
                            numberField(for: field, width: 80)
                            Text(field.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Stepper("", value: field.binding, in: 0...field.maxValue)
                                .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private func numberField(for field: FieldConfig, width: CGFloat) -> some View {
        TextField("", value: field.binding, format: .number)
            .font(FONT_EDIT)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
