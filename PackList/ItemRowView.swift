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
                    .onAppear { frame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { oldValue, newValue in
                        frame = newValue
                    }
            }
        )
        .onTapGesture {
            arrowEdge = arrowEdge(for: frame)
            editingItem = item
        }
        .popover(item: $editingItem, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { item in
            EditItemView(item: item)
                .presentationCompactAdaptation(.none)
                .background(Color.primary.opacity(0.2))
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
        let bottomSpace = screenHeight - frame.maxY
        return bottomSpace > topSpace ? .top : .bottom
    }
}


struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: M3Item
    @StateObject private var keyboardObserver = KeyboardObserver()
    @FocusState private var focusedField: Field?
    @State private var fieldFrames: [Field: CGRect] = [:]
    @State private var containerFrame: CGRect = .zero

    private enum Field: Hashable {
        case name
        case memo
        case weight
        case stock
        case need
    }

    private struct FieldFramePreferenceKey: PreferenceKey {
        static var defaultValue: [Field: CGRect] = [:]

        static func reduce(value: inout [Field: CGRect], nextValue: () -> [Field: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    private struct ContainerFramePreferenceKey: PreferenceKey {
        static var defaultValue: CGRect = .zero

        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            value = nextValue()
        }
    }

    private var keyboardOffset: CGFloat {
        guard keyboardObserver.keyboardHeight > 0,
              let focusedField,
              let fieldFrame = fieldFrames[focusedField],
              containerFrame != .zero else {
            return 0
        }

        let keyboardTop = UIScreen.main.bounds.height - keyboardObserver.keyboardHeight
        let safeMargin: CGFloat = 16
        let overlap = fieldFrame.maxY + safeMargin - keyboardTop
        guard overlap > 0 else { return 0 }

        let availableOffset = max(0, fieldFrame.minY - containerFrame.minY)
        return min(overlap, availableOffset)
    }

    private var weightBinding: Binding<Int> {
        Binding(get: { item.weight },
                set: {
//            item.weight = max(0, $0)
            // 数字以外を排除
//            let filtered = max(0, $0).filter { $0.isNumber }
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
            //item.stock = max(0, $0)
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
            //item.need = max(0, $0)
            let value = max(0, $0)
            if APP_MAX_NEED_NUM < value {
                item.need = APP_MAX_NEED_NUM
            } else {
                item.need = value
            }
        })
    }

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = geometry.safeAreaInsets.bottom
            let bottomPadding = max(0, keyboardObserver.keyboardHeight - bottomInset)

            ScrollView {
                VStack {
                    HStack {
                        Text("名称:")
                            .font(.caption)
                            .padding(4)
                        TextEditor(text: $item.name)
                            .onChange(of: item.name) { newValue, oldValue in
                                if APP_MAX_NAME_LEN < newValue.count {
                                    item.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                                }
                            }
                            .focused($focusedField, equals: .name)
                            .frame(width: 260, height: 80)
                            .padding(4)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: FieldFramePreferenceKey.self,
                                                           value: [.name: proxy.frame(in: .global)])
                                }
                            )
                    }
                    HStack {
                        Text("メモ:")
                            .font(.caption)
                            .padding(4)
                        TextEditor(text: $item.memo)
                            .onChange(of: item.memo) { newValue, oldValue in
                                if APP_MAX_MEMO_LEN < newValue.count {
                                    item.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                                }
                            }
                            .focused($focusedField, equals: .memo)
                            .frame(width: 260, height: 80)
                            .padding(4)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: FieldFramePreferenceKey.self,
                                                           value: [.memo: proxy.frame(in: .global)])
                                }
                            )
                    }
                    HStack {
                        Text("個重量:")
                            .font(.caption)
                        TextField("", value: weightBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .weight)
                            .background(Color.white.opacity(0.7))
                            .padding(4)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: FieldFramePreferenceKey.self,
                                                           value: [.weight: proxy.frame(in: .global)])
                                }
                            )
                        Text("ｇ")
                            .font(.caption)
                            .padding(4)
                        Stepper("", value: weightBinding, in: 0...APP_MAX_WEIGHT_NUM)
                            .labelsHidden()
                    }
                    HStack {
                        Text("在庫数:")
                            .font(.caption)
                        TextField("", value: stockBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .stock)
                            .background(Color.white.opacity(0.7))
                            .padding(4)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: FieldFramePreferenceKey.self,
                                                           value: [.stock: proxy.frame(in: .global)])
                                }
                            )
                        Text("個")
                            .font(.caption)
                            .padding(4)
                        Stepper("", value: stockBinding, in: 0...APP_MAX_STOCK_NUM)
                            .labelsHidden()
                    }
                    HStack {
                        Text("必要数:")
                            .font(.caption)
                        TextField("", value: needBinding, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .need)
                            .background(Color.white.opacity(0.7))
                            .padding(4)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(key: FieldFramePreferenceKey.self,
                                                           value: [.need: proxy.frame(in: .global)])
                                }
                            )
                        Text("個")
                            .font(.caption)
                            .padding(4)
                        Stepper("", value: needBinding, in: 0...APP_MAX_NEED_NUM)
                            .labelsHidden()
                    }
                }
                .padding()
                .frame(minWidth: 300)
            }
            .padding(.bottom, bottomPadding)
            .offset(y: -keyboardOffset)
            .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
            .animation(.easeOut(duration: 0.25), value: focusedField)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContainerFramePreferenceKey.self,
                                            value: proxy.frame(in: .global))
                }
            )
        }
        .onPreferenceChange(FieldFramePreferenceKey.self) { frames in
            fieldFrames = frames
        }
        .onPreferenceChange(ContainerFramePreferenceKey.self) { frame in
            containerFrame = frame
        }
        .onAppear {
            modelContext.undoManager?.beginUndoGrouping()
            if item.name.isEmpty {
                focusedField = .name
            }
        }
        .onDisappear {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            //try? modelContext.save() // Undoスタックがクリアされる
        }
    }
}

