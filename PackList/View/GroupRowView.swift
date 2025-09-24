//
//  GroupRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct GroupRowView: View {
    let group: M2Group
    let isHeader: Bool
    let onEdit: (M2Group, CGPoint) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { group.name.isEmpty }
    private var weightUnit: String { String(localized: "unit.gram") }

    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check || $0.need == 0 }
    }
    
    var body: some View {
        Group {
            HStack(spacing: 0) {
                Button { // 編集ボタン
                    if let rf = rowFrame {
                        let po = CGPoint(x: rf.width / 2.0,
                                         y: rf.minY)
                        onEdit(group, po)
                    }
                } label: {
                    Image(systemName: allItemsChecked ? "checkmark.rectangle" : "rectangle")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless) // これが無いとRow全域がタップ領域になる
                .tint(.accentColor)
                .padding(.vertical, 8)
                .padding(.trailing, 4)
                .padding(.leading, 0)

                VStack(alignment: .leading, spacing: 1) {
                    group.name.placeholderText("placeholder.group.new")
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                    
                    if !group.memo.isEmpty {
                        Text(group.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.leading, 25)
                    }
                    if DEBUG_SHOW_ORDER_ID {
                        Text("group (\(group.order)) [\(group.id)]")
                    }
                    
                    HStack {
                        Spacer() // 右寄せにするため
                        if 0 < group.stockWeight {
                            Text(verbatim: "\(group.stockWeight.decimalGrouped)\(weightUnit)／\(group.needWeight.decimalGrouped)\(weightUnit)")
                                .font(FONT_WEIGHT)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(COLOR_ROW_ITEM.opacity(0.85))
                                )
                        }
                        
                        if isHeader {
                            // セクションヘッダになる場合
                            // アイテム追加ボタン
                            Button(action: addItem) {
                                Image(systemName: "plus.circle")
                                    .imageScale(.large)
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
            .frame(minHeight: rowHeight)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .background(
                // Row本体に置くとRowサイズが固定化されてしまうため
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            rowFrame = geo.frame(in: .global)
                        }
                        .onChange(of: geo.frame(in: .global)) { newFrame, oldFrame in
                            rowFrame = newFrame
                        }
                }
            )
            .overlay(alignment: .bottom) {
                COLOR_LIST_SEPARATOR
                    .frame(height: LIST_SEPARATOR_THICKNESS)
                    .ignoresSafeArea(edges: .horizontal)
                    .padding(.leading, 20)
                    .padding(.trailing, 8)
            }
        }
    }

    private func addItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        let minOrder = group.child.map { $0.order }.min() ?? 0
        let newItem = M3Item(name: "", order: minOrder - 1, parent: group)
        modelContext.insert(newItem)
        withAnimation {
            group.child.insert(newItem, at: 0)
            group.normalizeItemOrder()
        }
    }

}

