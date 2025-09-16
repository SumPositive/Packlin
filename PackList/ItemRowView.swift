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
    let item: M3Item
    let onEdit: (M3Item, CGPoint) -> Void

    @Environment(\.modelContext) private var modelContext
   
    private let rowHeight: CGFloat = 44

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
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
        .padding(.leading, 0)
        .background(COLOR_ROW_ITEM)
        .transition(.move(edge: .top).combined(with: .opacity))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("itemList"))
                .onEnded { value in
                    let translation = value.translation
                    guard abs(translation.width) < 8, abs(translation.height) < 8 else { return }
                    onEdit(item, value.location)
                }
        )
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

}


