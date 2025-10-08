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
    @AppStorage(AppStorageKey.weightDisplayInKg) private var weightDisplayInKg: Bool = false

    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { group.name.isEmpty }
    private var weightUnit: String {
        weightDisplayInKg ? String(localized: "unit.kilogram") : String(localized: "unit.gram")
    }

    private var weightLabelText: String? {
        if showNeedWeight {
            guard group.stockWeight > 0 || group.needWeight > 0 else { return nil }
            return "\(formattedWeight(group.stockWeight))\(weightUnit)／\(formattedWeight(group.needWeight))\(weightUnit)"
        } else {
            guard group.stockWeight > 0 else { return nil }
            return "\(formattedWeight(group.stockWeight))\(weightUnit)"
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
    // 全アイテム数
    private var allItems: Int {
        return group.child.count
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
                        .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
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
                    // インデント
                    Rectangle()
                        .frame(width: 30, height: 1)
                        .foregroundStyle(.clear)

                    if let weightLabelText = weightLabelText {
                        Text(verbatim: weightLabelText)
                            .font(FONT_WEIGHT)
                            .foregroundStyle(COLOR_WEIGHT)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isHeader ? COLOR_ROW_BACK : COLOR_ROW_GROUP)
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
            //.padding(.top, isHeader ? 20 : 0) // セクションヘッダになる場合＋20
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

private extension GroupRowView {
    func formattedWeight(_ weight: Int) -> String {
        if weightDisplayInKg {
            // g -> Kgへ変換し、NumberFormatter側で小数第一位に丸める
            let kilogram = Double(weight) / 1000.0
            return kilogram.oneDecimalGrouped
        } else {
            return weight.decimalGrouped
        }
    }
}

