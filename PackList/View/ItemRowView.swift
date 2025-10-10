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

    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = false

    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { item.name.isEmpty }
    private var weightUnit: String { String(localized: "unit.gram") }
    private var hasClipboardItem: Bool { RowClipboard.item != nil }

    init(item: M3Item,
         onEdit: @escaping (M3Item, CGPoint) -> Void) {
        self.item = item
        self.onEdit = onEdit
    }
    // 数量表示Text
    private var quantityLabelText: String {
        var text: String = ""
        if 0 < item.weight {
            // 個重量
            text = "\(item.weight.decimalGrouped)\(weightUnit)　"
        }
        // 在庫数／必要数
        text += "\(item.stock.decimalGrouped)／\(item.need.decimalGrouped)"
        return text
    }


    var body: some View {
        HStack(spacing: 0) {
            // グループ縦線
            Rectangle()
                .fill(COLOR_ROW_GROUP)
                .frame(width: 12)
                .padding(.leading, 0)
                .padding(.trailing, 8)

            VStack(spacing: 0) {
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
                    .padding(.top, 8)
                    .padding(.bottom, 12)// タップ範囲を広げるため
                    .padding(.leading, 0)
                    .padding(.trailing, 8)
                    // 名称
                    item.name.placeholderText("placeholder.item.new")
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                    Spacer()
                }

                HStack(spacing: 0) {
                    // インデント
                    Rectangle()
                        .frame(width: 30, height: 1)
                        .foregroundStyle(.clear)

                    // 数量編集
                    Button {
                        guard let rf = rowFrame else { return }
                        let po = CGPoint(x: rf.width / 2.0,
                                         y: rf.minY)
                        onEdit(item, po)
                    } label: {
                        // 数量表示
                        Text(quantityLabelText)
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(COLOR_ROW_GROUP)
                    )

                    if !item.memo.isEmpty {
                        Text(item.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.leading, 4)
                    }
                    Spacer()
                }

                if DEBUG_SHOW_ORDER_ID {
                    Text("item (\(item.order)) [\(item.id)]")
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: rowHeight)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
        .padding(.leading, 0)
        .background(COLOR_ROW_BACK)
        .transition(.move(edge: .top).combined(with: .opacity))
        .contentShape(Rectangle())
        .background(
            // Row本体に置くとRowサイズが固定化されてしまうため
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        rowFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { oldFrame, newFrame in
                        rowFrame = newFrame
                    }
            }
        )
        .overlay(alignment: .bottom) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
                .ignoresSafeArea(edges: .horizontal)
                .padding(.leading, 50)
                .padding(.trailing, 30)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) { // 左スワイプ
            // Clipboard カット
            Button {
                cutItemToClipboard()
            } label: {
                Label("clipboard.cut", systemImage: "scissors")
            }
            .tint(.orange)
            .disabled(item.parent == nil)
            // Clipboard ペースト
            Button {
                /// Clipboard 上にペースト
                pasteItemAbove()
            } label: {
                Label("clipboard.paste", systemImage: "arrow.up.doc")
            }
            .tint(.green)
            .disabled(!hasClipboardItem || item.parent == nil)
            // Clipboard コピー
            Button {
                copyItemToClipboard()
            } label: {
                Label("clipboard.copy", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }

    /// 削除
    private func deleteItem() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
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

    /// Clipboard コピー
    private func copyItemToClipboard() {
        RowClipboard.clear()
        RowClipboard.item = cloneItem(item)
    }
    /// Clipboard カット
    private func cutItemToClipboard() {
        copyItemToClipboard()
        deleteItem()
    }
    /// Clipboard 上にペースト
    private func pasteItemAbove() {
        pasteItem(atOffset: 0)
    }
    /// Clipboard 下にペースト
    private func pasteItemBelow() {
        pasteItem(atOffset: 1)
    }
    /// Clipboard ペースト
    private func pasteItem(atOffset offset: Int) {
        guard let clipboardItem = RowClipboard.item,
              let parent = item.parent else { return }

        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        // 貼り付け先の order（表示順）を正しく推定するため、いったん order 順に並べ替える
        let orderedItems = parent.child.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }
        // 現在の行が表示順のどこにいるかを控えておく。見つからない場合は安全のため末尾挿入に切り替える
        let orderedIndex = orderedItems.firstIndex { $0.id == item.id } ?? orderedItems.count
        // offset を考慮した挿入位置を計算（上に貼る = 同じ位置、下に貼る = +1）
        let targetOrderedIndex = min(max(orderedIndex + offset, 0), orderedItems.count)

        // sparseOrderForInsertion を使って order の空き番号を算出する
        let newOrder = sparseOrderForInsertion(items: orderedItems, index: targetOrderedIndex) {
            // 空きがない場合は正規化してから再計算する
            parent.normalizeItemOrder()
        }

        let newItem = cloneItem(clipboardItem, parent: parent)
        newItem.order = newOrder
        modelContext.insert(newItem)

        let insertionIndex: Int
        if let currentIndex = parent.child.firstIndex(where: { $0.id == item.id }) {
            insertionIndex = min(max(currentIndex + offset, 0), parent.child.count)
        } else {
            insertionIndex = parent.child.count
        }

        withAnimation {
            if insertionIndex <= parent.child.count {
                parent.child.insert(newItem, at: insertionIndex)
            } else {
                parent.child.append(newItem)
            }
            parent.normalizeItemOrder()
        }
    }

}


