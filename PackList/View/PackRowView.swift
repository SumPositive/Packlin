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
    // 文字サイズ設定。「特大」のときだけ重量とメモを縦に分離する
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default

    @State private var rowFrame: CGRect?

    private var rowHeight: CGFloat { appRowHeight(fontScale) }
    private var weightLabelText: String? {
        if showNeedWeight {
            guard 0 < pack.stockWeight || 0 < pack.needWeight else { return nil }
            return formattedWeightProgress(stock: pack.stockWeight, need: pack.needWeight)
        } else {
            guard 0 < pack.stockWeight else { return nil }
            return formattedWeightWithUnit(pack.stockWeight)
        }
    }
    private var weightCapsuleState: QuantityCapsuleState {
        if allSufficientStock { return .just }
        return .over
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
                                .padding(.top, 5)
                        }
                        else if allSufficientStock {
                            Image(systemName: "circle")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                .padding(.top, 5)
                        }
                    }
                    .padding(.leading, 0)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                }
                .buttonStyle(BorderlessButtonStyle())
                // 名称
                pack.name.placeholderText("new.pack")
                    .lineLimit(3, reservesSpace: false)
                    .font(FONT_NAME)
                    .foregroundStyle(pack.name.isEmpty ? .secondary : COLOR_NAME)
                Spacer()
            }
            
            // 文字サイズ「特大」のときだけ、重量とメモを上下に分離して欠落を防ぐ
            if fontScale == .xLarge {
                // 「特大」: 2行目に重量（左寄せ）、3行目にメモ（左寄せ）
                HStack(spacing: 0) {
                    indentSpacer
                    weightBadgeOrSpacer
                    Spacer(minLength: 0)
                }
                HStack(spacing: 0) {
                    indentSpacer
                    memoView
                    Spacer(minLength: 0)
                }
            } else {
                // 「自動」「標準」「大」: 重量バッジとメモを同じ行に並べる（従来の動作）
                HStack(spacing: 0) {
                    indentSpacer
                    weightBadgeOrSpacer
                    memoView
                    Spacer(minLength: 0)
                }
            }
            // DEBUG Line
            if DEBUG_SHOW_ORDER_ID {
                Text("pack (\(pack.order)) [\(pack.id)]")
            }
        }
        .frame(minHeight: rowHeight)
        // 行コンテナの上下余白を文字サイズに合わせて広げる（大: 12pt、特大: 16pt）
        .padding(.vertical, appRowVerticalPadding(fontScale))
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
                Label("delete", systemImage: "trash")
            }
            .tint(.red)
            
            // パック複製
            Button {
                pack.duplicate()
            } label: {
                Label("copy", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
    }

}

private extension PackRowView {
    /// 行先頭のインデント（30pt の透明スペース）
    @ViewBuilder
    var indentSpacer: some View {
        Rectangle()
            .frame(width: 30, height: 1)
            .foregroundStyle(.clear)
    }

    /// 重量バッジ。重量がないときはバッジ幅相当の透明スペースを返して見た目を揃える
    @ViewBuilder
    var weightBadgeOrSpacer: some View {
        if let weightLabelText {
            infoCapsule(weightLabelText, state: weightCapsuleState)
        } else {
            Rectangle()
                .frame(width: 24, height: 1)
                .foregroundStyle(.clear)
        }
    }

    /// メモ（または初心者向けの空アイテム説明）
    @ViewBuilder
    var memoView: some View {
        if isBeginnerMode, pack.name.isEmpty, pack.memo.isEmpty {
            Text("packs.gather.everything.bag.backpack")
                .lineLimit(3)
                .font(FONT_MEMO)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                // 初心者ヘルプ（プレースホルダー説明文）を「大」までで頭打ち
                .cappedAtLargeFontSize()
        } else {
            Text(pack.memo)
                .lineLimit(3, reservesSpace: false)
                .font(FONT_MEMO)
                .foregroundStyle(COLOR_MEMO)
                .padding(.horizontal, 8)
        }
    }

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

    func formattedWeightProgress(stock: Int, need: Int) -> String {
        if 0 < need, stock == need {
            return formattedWeightWithUnit(need)
        }

        if weightDisplayInKg, 1000 <= stock || 1000 <= need {
            let stockKilogram = Double(stock) / 1000.0
            let needKilogram = Double(need) / 1000.0
            return "\(stockKilogram.oneDecimalGrouped)/\(needKilogram.oneDecimalGrouped)\(String(localized: "kg"))"
        }

        return "\(stock.decimalGrouped)/\(need.decimalGrouped)\(String(localized: "g"))"
    }

    @ViewBuilder
    func infoCapsule(_ text: String, state: QuantityCapsuleState) -> some View {
        compactSlashText(text)
            .font(FONT_WEIGHT)
            .foregroundStyle(state.foregroundStyle)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(state.backgroundStyle(defaultColor: COLOR_ROW_GROUP))
            )
    }

    @ViewBuilder
    func compactSlashText(_ text: String) -> some View {
        // バッジ内のテキストは絶対に折り返さない。折り返したいときは外側の
        // ViewThatFits で行レイアウト自体を切り替える
        if let slashIndex = text.firstIndex(of: "/") {
            let left = String(text[..<slashIndex])
            let right = String(text[text.index(after: slashIndex)...])
            HStack(spacing: 1) {
                Text(verbatim: left)
                Text(verbatim: "/")
                Text(verbatim: right)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        } else {
            Text(verbatim: text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
