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
    @State private var rowFrame: CGRect?
    @State private var checkButtonFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { item.name.isEmpty }
    private var weightUnit: String { String(localized: "unit.gram") }

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
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            checkButtonFrame = geo.frame(in: .global)
                        }
                        .onChange(of: geo.frame(in: .global)) { newFrame, _ in
                            checkButtonFrame = newFrame
                        }
                }
            )

            VStack(alignment: .leading, spacing: 1){
                item.name.placeholderText("placeholder.item.new")
                    .lineLimit(3)
                    .font(FONT_NAME)
                    .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)

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
                        Text(verbatim: "［\(item.weight)\(weightUnit)］")
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)

                        Text(verbatim: "\(item.stock * item.weight)\(weightUnit)／\(item.need * item.weight)\(weightUnit)")
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
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard let rf = rowFrame else { return }
                    let location = value.location
                    let globalLocation = CGPoint(x: rf.minX + location.x,
                                                 y: rf.minY + location.y)
                    if let checkButtonFrame,
                       checkButtonFrame.contains(globalLocation) {
                        return
                    }
                    let po = CGPoint(x: rf.width / 2.0,
                                     y: globalLocation.y)
                    onEdit(item, po)
                }
        )
        .overlay(alignment: .bottom) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
                .ignoresSafeArea(edges: .horizontal)
                .padding(.leading, 12)
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

}


