//
//  ItemEditView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//
//　Item移動がGroupを超えて可能にするためListでなくLazyVStackを利用、そのため
//　RowのswipeActionsが使えなくなるので、ItemEditView上にActionsボタンを表示することにした
//

import SwiftUI
import SwiftData

enum ItemEditPresentationStyle {
    case popup
    case navigation
}

/// Item 編集
/// 外枠 frameを固定サイズにして、内側をレイアウトしている
struct ItemEditView: View {
    @Bindable var item: M3Item
    let style: ItemEditPresentationStyle
    let onClose: () -> Void

    init(item: M3Item,
         style: ItemEditPresentationStyle = .popup,
         onClose: @escaping () -> Void) {
        self._item = Bindable(item)
        self.style = style
        self.onClose = onClose
    }

    @Environment(\.modelContext) private var modelContext
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
            // チェック更新
            item.check = (0 < item.stock && item.need <= item.stock)
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
            // チェック更新
            item.check = (0 < item.stock && item.need <= item.stock)
        })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("edit.name")
                    .font(.caption)
                    .padding(4)
                Spacer()
            }
            .padding(.bottom, -3)
            TextEditor(text: $item.name)
                .font(FONT_EDIT)
                .onChange(of: item.name) { newValue, oldValue in
                    // 最大文字数制限
                    if APP_MAX_NAME_LEN < newValue.count {
                        item.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                    }
                }
                .focused($nameIsFocused) // フォーカス状態とバインド
                .frame(height: 80)

            HStack {
                Text("edit.memo")
                    .font(.caption)
                Spacer()
            }
            .padding(.top, 8)
            //.padding(.bottom, 0)
            TextEditor(text: $item.memo)
                .font(FONT_EDIT)
                .onChange(of: item.memo) { newValue, oldValue in
                    // 最大文字数制限
                    if APP_MAX_MEMO_LEN < newValue.count {
                        item.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                    }
                }
                .frame(height: 80)

            HStack {
                // Action ボタン
                VStack {
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
                    .padding(8)
                    
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
                    .padding(8)
                }

                // 重量・数量
                VStack(spacing: 0) {
                    HStack {
                        Text("item.field.weight")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.bottom, -2)
                    HStack {
                        TextField("", value: weightBinding, format: .number)
                            .font(FONT_EDIT)
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .background(Color(.systemBackground))
                        Text("unit.gram")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: weightBinding, in: 0...APP_MAX_WEIGHT_NUM)
                            .labelsHidden()
                    }
                    .padding(.bottom, 8)
                    HStack {
                        Text("item.field.stock")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.bottom, -2)
                    HStack {
                        TextField("", value: stockBinding, format: .number)
                            .font(FONT_EDIT)
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .background(Color(.systemBackground))
                        Text("unit.piece")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: stockBinding, in: 0...APP_MAX_STOCK_NUM)
                            .labelsHidden()
                    }
                    .padding(.bottom, 8)
                    HStack {
                        Text("item.field.need")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.bottom, -2)
                    HStack {
                        TextField("", value: needBinding, format: .number)
                            .font(FONT_EDIT)
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .background(Color(.systemBackground))
                        Text("unit.piece")
                            .font(.caption)
                        Spacer()
                        Stepper("", value: needBinding, in: 0...APP_MAX_NEED_NUM)
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(8)
        }
        .padding(8)
        .frame(width: style == .popup ? 320 : nil,
               height: style == .popup ? 368 : nil) // H:380以内にしないとキーボードが被る恐れあり
        .frame(maxWidth: style == .navigation ? .infinity : nil)
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


