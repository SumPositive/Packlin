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

    @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = false

    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { group.name.isEmpty }
    private var weightUnit: String { String(localized: "unit.gram") }

    private var weightLabelText: String? {
        if showNeedWeight {
            guard group.stockWeight > 0 || group.needWeight > 0 else { return nil }
            return "\(group.stockWeight.decimalGrouped)\(weightUnit)／\(group.needWeight.decimalGrouped)\(weightUnit)"
        } else {
            guard group.stockWeight > 0 else { return nil }
            return "\(group.stockWeight.decimalGrouped)\(weightUnit)"
        }
    }
    // 全チェック済み
    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check || $0.need == 0 }
    }
    // 全充足（不足なし）  "Sufficient stock"
    private var allSufficientStock: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.need == 0 || $0.need <= $0.stock }
    }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // 編集
                    Button {
                        guard let rf = rowFrame else { return }
                        let po = CGPoint(x: rf.width / 2.0,
                                         y: rf.minY)
                        onEdit(group, po)
                    } label: {
                        Image(systemName
                              : allItemsChecked ? "checkmark.square"
                              : allSufficientStock ? "circle.square"
                              : "square")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            .padding(.leading, 0)
                            .padding(.trailing, 8)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    // 名称
                    group.name.placeholderText("placeholder.group.new")
                        .lineLimit(3)
                        .font(FONT_NAME)
                        .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                    Spacer()
                }
                
                HStack(spacing: 0) {
                    Rectangle()
                        .frame(width: 24, height: 1)
                        .foregroundStyle(.clear)

                    if let weightLabelText = weightLabelText {
                        Text(verbatim: weightLabelText)
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(COLOR_ROW_ITEM.opacity(0.85))
                            )
                    }else{
                        Rectangle()
                            .frame(width: 24, height: 1)
                            .foregroundStyle(.clear)
                    }
                    // メモ
                    if !group.memo.isEmpty {
                        Text(group.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.horizontal, 8)
                    }
                    Spacer()

                    if isHeader {
                        // セクションヘッダになる場合
                    }
                }
                // DEBUG Line
                if DEBUG_SHOW_ORDER_ID {
                    Text("group (\(group.order)) [\(group.id)]")
                }
            }
            .frame(minHeight: rowHeight)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
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
                if !isHeader {
                    COLOR_LIST_SEPARATOR
                        .frame(height: LIST_SEPARATOR_THICKNESS)
                        .ignoresSafeArea(edges: .horizontal)
                        .padding(.horizontal, 50)
                }
            }
        }
    }

}

