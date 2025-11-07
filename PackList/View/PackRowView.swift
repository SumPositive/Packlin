//
//  PackRowView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit

struct PackRowView: View {
    let pack: M1Pack
    let onEdit: (M1Pack, CGPoint) -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = false
    @AppStorage(AppStorageKey.weightDisplayInKg) private var weightDisplayInKg: Bool = false
    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { pack.name.isEmpty }
    private var weightUnit: String {
        weightDisplayInKg ? String(localized: "kg") : String(localized: "g")
    }

    private var weightLabelText: String? {
        if showNeedWeight {
            guard pack.stockWeight > 0 || pack.needWeight > 0 else { return nil }
            return "\(formattedWeight(pack.stockWeight))\(weightUnit)／\(formattedWeight(pack.needWeight))\(weightUnit)"
        } else {
            guard pack.stockWeight > 0 else { return nil }
            return "\(formattedWeight(pack.stockWeight))\(weightUnit)"
        }
    }
    // 全チェック済み
    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check || $0.need == 0 }
    }
    // 全充足（不足なし）  "Sufficient stock"
    private var allSufficientStock: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.need == 0 || $0.need <= $0.stock }
    }
    // 全アイテム数
    private var allItems: Int {
        let items = pack.child.flatMap { $0.child }
        return items.count
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
                        onEdit(pack, po)
                    } label: {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating) // Once

                            if allItemsChecked {
                                Image(systemName: "checkmark")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                    .padding(.top, 4)
                            }
                            else if allSufficientStock {
                                Image(systemName: "circle")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.leading, 0)
                        .padding(.trailing, 8)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    // 名称
                    pack.name.placeholderText("新しいパック")
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
                                    .fill(COLOR_ROW_GROUP)
                            )
                    }else{
                        Rectangle()
                            .frame(width: 24, height: 1)
                            .foregroundStyle(.clear)
                    }
                    // メモ
                    if !pack.memo.isEmpty {
                        Text(pack.memo)
                            .lineLimit(3)
                            .font(FONT_MEMO)
                            .foregroundStyle(COLOR_MEMO)
                            .padding(.horizontal, 8)
                    }
                    Spacer()
                }
                // DEBUG Line
                if DEBUG_SHOW_ORDER_ID {
                    Text("pack (\(pack.order)) [\(pack.id)]")
                }
            }
            .frame(minHeight: rowHeight)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
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
                // 独自の下線
                COLOR_LIST_SEPARATOR
                    .frame(height: LIST_SEPARATOR_THICKNESS)
                    .ignoresSafeArea(edges: .horizontal)
                    .padding(.horizontal, 50)
            }
        }
    }

}

private extension PackRowView {
    func formattedWeight(_ weight: Int) -> String {
        if weightDisplayInKg {
            // g単位の値をKgへ変換し、Formatterで小数第一位に丸める
            let kilogram = Double(weight) / 1000.0
            return kilogram.oneDecimalGrouped
        } else {
            return weight.decimalGrouped
        }
    }
}

