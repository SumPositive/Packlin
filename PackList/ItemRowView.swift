//
//  ItemRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct ItemRowView: View {
    @Environment(\.modelContext) private var modelContext
    let item: M3Item
    
    @State private var editingItem: M3Item?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
   
    private let rowHeight: CGFloat = 44

    init(item: M3Item) {
        self.item = item
    }


    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(COLOR_ROW_GROUP)
                .frame(width: 12)
                .padding(.leading, 0)
                .padding(.trailing, 8)

            Button {
                item.check.toggle()
                if item.check {
                    item.stock = item.need
                }else{
                    item.stock = 0
                }
            } label: {
                Image(systemName: item.check ? "checkmark.circle"
                      : 0 < item.need ? "circle" : "circle.dotted")
            }
            .buttonStyle(BorderlessButtonStyle())
            .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 1){
                Text(item.name.isEmpty ? "New Item" : item.name)
                    .lineLimit(3)
                    .font(FONT_NAME)
                    .foregroundStyle(item.name.isEmpty ? .secondary : COLOR_NAME)

                if !item.memo.isEmpty {
                    Text(item.memo)
                        .lineLimit(3)
                        .font(FONT_MEMO)
                        .foregroundStyle(COLOR_MEMO)
                        .padding(.leading, 25)
                }
                if DEBUG_SHOW_ORDER_ID {
                    Text("item (\(item.order)) [\(item.id)]")
                }
                
                HStack {
                    Spacer() // 右寄せにするため
                    if 0 < item.weight {
                        Text("［\(item.weight)g］")
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)

                        Text("\(item.stock * item.weight)g／\(item.need * item.weight)g")
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)
                            .padding(.trailing, 4)
                    }
                    Text("\(item.stock)／\(item.need)")
                        .font(FONT_STOCK)
                        .foregroundStyle(COLOR_WEIGHT)
                        .padding(.trailing, 40)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: rowHeight)
        .padding(.leading, 0)
        .swipeActions(edge: .trailing) {
            Button("Cut") {
                copyToClipboard()
                deleteItem()
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading) {
            Button("Copy") {
                copyToClipboard()
            }
            .tint(.cyan)

            Button("Paste") {
                pasteFromClipboard()
            }
            //.disabled(RowClipboard.item == nil)
            .tint(.blue)

            Button("Duplicate") {
                duplicateItem()
            }
            .tint(.green)
        }
        .contentShape(Rectangle())
        .background(COLOR_ROW_ITEM)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        frame = proxy.frame(in: .global)
                    }
                    .onChange(of: proxy.frame(in: .global)) { oldValue, newValue in
                        frame = newValue
                    }
            }
        )
        .onTapGesture {
            arrowEdge = arrowEdge(for: frame)
            editingItem = item
        }
        .popover(item: $editingItem) { item in
            EditItemView(item: item)
                .presentationCompactAdaptation(.none)
                .background(Color.primary.opacity(0.2))
                .ignoresSafeArea(.keyboard) // これを付けると“圧縮”が起きにくくなる
        }
        .transition(.move(edge: .top).combined(with: .opacity))
       .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
    }

    private func deleteItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        if let parent = item.parent,
           let index = parent.child.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                parent.child.remove(at: index)
                parent.normalizeItemOrder()
            }
        }
        modelContext.delete(item)
    }

    private func duplicateItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        guard let parent = item.parent else { return }
        let newItem = M3Item(name: item.name, memo: item.memo, stock: item.stock, need: item.need, weight: item.weight, order: item.order, parent: parent)
        modelContext.insert(newItem)
        withAnimation {
            if let index = parent.child.firstIndex(where: { $0.id == item.id }) {
                parent.child.insert(newItem, at: index)
            } else {
                parent.child.append(newItem)
            }
            parent.normalizeItemOrder()
        }
    }

    private func copyToClipboard() {
        RowClipboard.clear()
        RowClipboard.item = cloneItem(item)
    }

    private func pasteFromClipboard() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        guard let clip = RowClipboard.item, let parent = item.parent else { return }
        let newItem = cloneItem(clip, parent: parent)
        newItem.order = item.order
        modelContext.insert(newItem)
        withAnimation {
            // 現在行(index)を求めその行に追加する
            if let index = parent.child.firstIndex(where: { $0.id == item.id }) {
                // index位置に追加
                parent.child.insert(newItem, at: index)
            } else {
                // 末尾に追加
                parent.child.append(newItem)
            }
            parent.normalizeItemOrder()
        }
    }

    private func arrowEdge(for frame: CGRect?) -> Edge {
        guard let frame = frame else { return .bottom }
        let screenHeight = UIScreen.main.bounds.height
        let topSpace = frame.minY
        let bottomSpace = screenHeight - frame.maxY  //-300:popover内容max高さ

        if topSpace < bottomSpace {
            popoverBottom = frame.maxY + 280 + 40
            return .top
        }else{
            popoverBottom = 0 // 背面スライドUPしない。popoverだけがスライドUPしてくれる
            return .bottom
        }
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
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            //try? modelContext.save() // Undoスタックがクリアされる
        }
    }
}

