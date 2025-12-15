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

    @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = DEF_showNeedWeight
    @AppStorage(AppStorageKey.weightDisplayInKg) private var weightDisplayInKg: Bool = DEF_weightDisplayInKg
    // 表示モード（初心者／達人）を同じキーで共有し、ヘッダー表示を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    @AppStorage(AppStorageKey.rowTextLines) private var rowTextLines: RowTextLines = .default

    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { group.name.isEmpty }
    private var weightLabelText: String? {
        if showNeedWeight {
            guard 0 < group.stockWeight || 0 < group.needWeight else { return nil }
            // 表示単位は重量ごとに決めるため、gとkgが混在するケースにも対応する
            let stockText = formattedWeightWithUnit(group.stockWeight)
            let needText  = formattedWeightWithUnit(group.needWeight)
            return "\(stockText)／\(needText)"
        } else {
            guard 0 < group.stockWeight else { return nil }
            return formattedWeightWithUnit(group.stockWeight)
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
    // 説明文を出すかどうかのフラグを共通にまとめる
    private var isBeginnerMode: Bool { displayMode == .beginner }
    // 行数設定をまとめた補助値
    private var nameLineLimit: Int { rowTextLines.nameLineLimit }
    private var memoLineLimit: Int { rowTextLines.memoLineLimit }
    private var showMemo: Bool { 0 < memoLineLimit }
    private var showWeightOnNameLine: Bool { rowTextLines.placeAccessoryOnNameLine }
    private var detailRowNeeded: Bool {
        // memo表示の有無と重量表示位置で二段目を出すか判定する
        if showMemo {
            return true
        }
        if showWeightOnNameLine {
            return false
        }
        return weightLabelText != nil
    }


    var body: some View {
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
                group.name.placeholderText("新しいグループ")
                    // 長い名称も折り返しで見せる
                    .lineLimit(nameLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(FONT_NAME)
                    .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                Spacer()
                // 最小表示時は重量を右側へ寄せる
                if showWeightOnNameLine, let weightLabelText {
                    weightLabel(weightLabelText)
                        .padding(.leading, 8)
                }
            }

            if detailRowNeeded {
                HStack(spacing: 0) {
                    // インデント
                    Rectangle()
                        .frame(width: 30, height: 1)
                        .foregroundStyle(.clear)

                    let weightOnSecondRow = !showWeightOnNameLine && weightLabelText != nil

                    if weightOnSecondRow, let weightLabelText {
                        weightLabel(weightLabelText)
                    }else{
                        Rectangle()
                            .frame(width: 24, height: 1)
                            .foregroundStyle(.clear)
                    }
                    // メモ
                    if showMemo {
                        if isBeginnerMode, group.name.isEmpty, group.memo.isEmpty {
                            Text("グループとは、持ち物をポーチなどで小分けにしたものです")
                                .lineLimit(memoLineLimit)
                                .font(FONT_MEMO)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                        }else{
                            Text(group.memo)
                                .lineLimit(memoLineLimit)
                                .font(FONT_MEMO)
                                .foregroundStyle(COLOR_MEMO)
                                .padding(.horizontal, 8)
                        }
                    }
                    Spacer()

                    if isHeader {
                        // セクションヘッダになる場合
                    }
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
        //.contentShape(Rectangle()) // 全体をタップ可能領域にする
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
        .background(isHeader ? COLOR_ROW_GROUP : COLOR_ROW_BACK)
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

private extension GroupRowView {
    func formattedWeightWithUnit(_ weight: Int) -> String {
        // 重量表示の単位を重量値ごとに動的決定する
        if weightDisplayInKg {
            // 1000g未満はgのまま表示し、ちょうど1000g以上になったらkgへ変換する
            if weight < 1000 {
                return "\(weight.decimalGrouped)\(String(localized: "g"))"
            }
            // kg表示時は小数第一位までに丸めて見やすくする
            let kilogram = Double(weight) / 1000.0
            return "\(kilogram.oneDecimalGrouped)\(String(localized: "kg"))"
        }
        // 設定オフ時は常にg単位で表示する
        return "\(weight.decimalGrouped)\(String(localized: "g"))"
    }

    /// 重量カプセルの共通ビュー
    @ViewBuilder
    func weightLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(FONT_WEIGHT)
            .foregroundStyle(COLOR_WEIGHT)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isHeader ? COLOR_ROW_BACK : COLOR_ROW_GROUP)
            )
    }
}

