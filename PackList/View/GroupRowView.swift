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
        !group.child.isEmpty && group.child.allSatisfy { $0.check }
    }
    
    var body: some View {
        Group {
            HStack(spacing: 12) {
                Capsule()
                    .fill(COLOR_ROW_GROUP)
                    .frame(width: 8)
                    .padding(.vertical, 10)

                Image(systemName: allItemsChecked ? "checkmark.rectangle" : "rectangle")
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(COLOR_ROW_GROUP.opacity(0.6))
                    )

                VStack(alignment: .leading, spacing: 6) {
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
                    
                    HStack(spacing: 8) {
                        Spacer() // 右寄せにするため
                        if 0 < group.stockWeight {
                            Text(verbatim: "\(group.stockWeight)\(weightUnit)／\(group.needWeight)\(weightUnit)")
                                .font(FONT_WEIGHT)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(COLOR_ROW_ITEM.opacity(0.7))
                                )
                        }

                        if isHeader {
                            Button(action: addItem) {
                                Image(systemName: "plus.circle")
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(COLOR_ROW_GROUP.opacity(0.7))
                                    )
                            }
                        }
                    }
                }
                Spacer()
            }
            .frame(minHeight: rowHeight)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(COLOR_ROW_GROUP.opacity(0.8))
            )
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
                        let po = CGPoint(x: rf.width / 2.0,
                                         y: rf.minY + location.y)
                        onEdit(group, po)
                    }
            )
        }
    }

    private func addItem() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }

        let newItem = M3Item(name: "", order: group.nextItemOrder(), parent: group)
        modelContext.insert(newItem)
        withAnimation {
            group.child.append(newItem)
            group.normalizeItemOrder()
        }
    }
    
}

