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
    @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = DEF_showNeedWeight
    @AppStorage(AppStorageKey.weightDisplayInKg) private var weightDisplayInKg: Bool = DEF_weightDisplayInKg
    // 表示モード（初心者／達人）を同じキーで共有し、ヘッダー表示を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default

    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var weightLabelText: String? {
        if showNeedWeight {
            guard 0 < pack.stockWeight || 0 < pack.needWeight else { return nil }
            // 表示単位は重量ごとに個別判定し、g表示とkg表示の混在を許容する
            let stockText = formattedWeightWithUnit(pack.stockWeight)
            let needText  = formattedWeightWithUnit(pack.needWeight)
            return "\(stockText)／\(needText)"
        } else {
            guard 0 < pack.stockWeight else { return nil }
            return formattedWeightWithUnit(pack.stockWeight)
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
    // 説明文を出すかどうかのフラグを共通にまとめる
    private var isBeginnerMode: Bool { displayMode == .beginner }

    
    var body: some View {
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
                    .lineLimit(3, reservesSpace: false)
                    .font(FONT_NAME)
                    .foregroundStyle(pack.name.isEmpty ? .secondary : COLOR_NAME)
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
                if isBeginnerMode, pack.name.isEmpty, pack.memo.isEmpty {
                    Text("パックとは、持ち物をバッグやリュックに全てまとめたものです")
                        .lineLimit(3)
                        .font(FONT_MEMO)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }else{
                    Text(pack.memo)
                        .lineLimit(3, reservesSpace: false)
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
        .background(COLOR_ROW_BACK)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { // 左スワイプ・アクション（フルスワイプ即削除を無効化）
            // パック削除（ワンタップでのみ削除されるようにして事故を防ぐ）
            Button {
                pack.delete()
            } label: {
                Label("削除", systemImage: "trash")
            }
            .tint(.orange)
            
            // パック複製
            Button {
                pack.duplicate()
            } label: {
                Label("複製", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
    }

}

private extension PackRowView {
    func formattedWeightWithUnit(_ weight: Int) -> String {
        // 重量値に応じて単位を切り替え、見やすい表記に整える
        if weightDisplayInKg {
            // 1000g未満は従来どおりgで表示し、1000g以上はkgで丸める
            if weight < 1000 {
                return "\(weight.decimalGrouped)\(String(localized: "g"))"
            }
            let kilogram = Double(weight) / 1000.0
            return "\(kilogram.oneDecimalGrouped)\(String(localized: "kg"))"
        }
        return "\(weight.decimalGrouped)\(String(localized: "g"))"
    }
}

