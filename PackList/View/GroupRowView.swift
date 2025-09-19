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
            HStack(spacing: 0) {
                Image(systemName: allItemsChecked ? "checkmark.rectangle" : "rectangle")
                    .padding(.trailing, 8)

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
                            Text(verbatim: "\(group.stockWeight)\(weightUnit)／\(group.needWeight)\(weightUnit)")
                                .font(FONT_WEIGHT)
                                .foregroundStyle(COLOR_WEIGHT)
                                .padding(.trailing, 4)
                        }
                        
                        if isHeader {
                            Button(action: addItem) {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
                Spacer()
            }
            .frame(minHeight: rowHeight)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 16)
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

