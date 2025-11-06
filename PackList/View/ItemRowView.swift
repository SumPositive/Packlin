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
                    item.name.placeholderText("新しいアイテム")
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
            // アイテム削除
            Button {
                deleteItem()
            } label: {
                Label("削除", systemImage: "trash")
            }
            .tint(.orange)
            .disabled(item.parent == nil)
            // アイテム複製
            Button {
                duplicateItem()
            } label: {
                Label("複製", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
    }

    /// アイテム削除
    private func deleteItem() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
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

    /// アイテム複製
    private func duplicateItem() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
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

}


