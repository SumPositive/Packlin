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
        DisclosureGroup(isExpanded: Binding(get: { item.isExpanded }, set: { item.isExpanded = $0 })) {
            if !item.child.isEmpty {
                ForEach(item.child.sorted { $0.order < $1.order }) { child in
                    ItemRowView(item: child)
                }
            }
        } label: {
            rowContent
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
    }

    private var rowContent: some View {
        HStack {
            Rectangle()
                .fill(COLOR_ROW_PACK)
                .frame(width: 8)
                .padding(.horizontal, 0)

            Rectangle()
                .fill(COLOR_ROW_GROUP)
                .frame(width: 8)
                .padding(.leading, -8)
                .padding(.trailing, 8)

            Button {
                item.check.toggle()
                if item.check {
                    item.stock = item.need
                } else {
                    item.stock = 0
                }
            } label: {
                Image(systemName: item.check ? "checkmark.circle"
                      : 0 < item.need ? "circle" : "circle.dotted")
            }
            .buttonStyle(BorderlessButtonStyle())
            .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 1) {
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
    }

    private func deleteItem() {
        if let pItem = item.parentItem,
           let index = pItem.child.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                pItem.child.remove(at: index)
            }
        } else if let parent = item.parent,
                  let index = parent.child.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                parent.child.remove(at: index)
                parent.normalizeItemOrder()
            }
        }
        modelContext.delete(item)
    }

    private func duplicateItem() {
        guard let parent = item.parent else { return }
        let newItem = M3Item(name: item.name,
                             memo: item.memo,
                             stock: item.stock,
                             need: item.need,
                             weight: item.weight,
                             order: item.order,
                             parent: parent,
                             parentItem: item.parentItem,
                             isExpanded: item.isExpanded)
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
        guard let clip = RowClipboard.item, let parent = item.parent else { return }
        let newItem = cloneItem(clip, parent: parent, parentItem: item.parentItem)
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
    @Environment(\.modelContext) private var context
    @Bindable var item: M3Item

    private var stockBinding: Binding<Int> {
        Binding(get: { item.stock }, set: { item.stock = max(0, $0) })
    }
    private var needBinding: Binding<Int> {
        Binding(get: { item.need }, set: { item.need = max(0, $0) })
    }
    private var weightBinding: Binding<Int> {
        Binding(get: { item.weight }, set: { item.weight = max(0, $0) })
    }

    var body: some View {
        VStack {
            HStack {
                Text("名称:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $item.name, prompt: Text("New Item name"))
                    .background(Color.white.opacity(0.7))
                    .padding(4)
            }
            HStack {
                Text("メモ:")
                    .font(.caption)
                    .padding(4)
                TextField("", text: $item.memo)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
            }
            HStack {
                Text("個重量:")
                    .font(.caption)
                TextField("", value: weightBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
                Text("ｇ")
                    .font(.caption)
                    .padding(4)
                Stepper("", value: weightBinding, in: 0...Int.max)
                    .labelsHidden()
            }
            HStack {
                Text("在庫数:")
                    .font(.caption)
                TextField("", value: stockBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
                Text("個")
                    .font(.caption)
                    .padding(4)
                Stepper("", value: stockBinding, in: 0...Int.max)
                    .labelsHidden()
            }
            HStack {
                Text("必要数:")
                    .font(.caption)
                TextField("", value: needBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .background(Color.white.opacity(0.7))
                    .padding(4)
                Text("個")
                    .font(.caption)
                    .padding(4)
                Stepper("", value: needBinding, in: 0...Int.max)
                    .labelsHidden()
            }
//            HStack {
//                Spacer()
//                Button("Done") {
//                    try? context.save()
//                    dismiss()
//                }
//            }
        }
        .padding()
        .frame(minWidth: 300)
        .onDisappear() {
            try? context.save()
        }
    }
}

