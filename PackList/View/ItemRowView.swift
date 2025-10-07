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
                    Rectangle()
                        .frame(width: 24, height: 1)
                        .foregroundStyle(.clear)

                    // 数量編集
                    Button {
                        guard let rf = rowFrame else { return }
                        let po = CGPoint(x: rf.width / 2.0,
                                         y: rf.minY)
                        onEdit(item, po)
                    } label: {
                        if 0 < item.weight {
                            // 個重量
                            Text(verbatim: "\(item.weight.decimalGrouped)\(weightUnit)")
                                .font(FONT_STOCK)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            
                        }
                        // 在庫数／必要数
                        Text("\(item.stock.decimalGrouped)／\(item.need.decimalGrouped)")
                            .font(FONT_STOCK)
                            .foregroundStyle(COLOR_WEIGHT)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                        //Image(systemName: "square.and.pencil")
                        //    .tint(.accentColor).opacity(0.7)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.horizontal, 8)
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
    }

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

}


