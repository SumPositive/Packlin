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

    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock
    @AppStorage(AppStorageKey.linkCheckOffWithZero) private var linkCheckOffWithZero: Bool = DEF_linkCheckOffWithZero
    // 表示モード（初心者／達人）を同じキーで共有し、ヘッダー表示を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    @AppStorage(AppStorageKey.rowTextLines) private var rowTextLines: RowTextLines = .default

    @State private var rowFrame: CGRect?

    private let rowHeight: CGFloat = 44
    private var isNamePlaceholder: Bool { item.name.isEmpty }
    private var weightUnit: String { String(localized: "g") }
    // 説明文を出すかどうかのフラグを共通にまとめる
    private var isBeginnerMode: Bool { displayMode == .beginner }
    // 行数設定をまとめた補助値
    private var nameLineLimit: Int { rowTextLines.nameLineLimit }
    private var memoLineLimit: Int { rowTextLines.memoLineLimit }
    private var showMemo: Bool { 0 < memoLineLimit }
    private var showQuantityOnNameLine: Bool { rowTextLines.placeAccessoryOnNameLine }
    private var isExtraSmallRow: Bool { rowTextLines.usesExtraSmallItemRow }
    private var itemRowHeight: CGFloat { isExtraSmallRow ? 38 : rowHeight }
    private var contentVerticalPadding: CGFloat { isExtraSmallRow ? 0 : 4 }
    private var checkTopPadding: CGFloat { isExtraSmallRow ? 0 : 8 }
    private var checkBottomPadding: CGFloat { isExtraSmallRow ? 0 : 12 }
    private var checkTrailingPadding: CGFloat { isExtraSmallRow ? 5 : 8 }
    private var quantityHorizontalPadding: CGFloat { isExtraSmallRow ? 4 : 5 }
    private var quantityVerticalPadding: CGFloat { isExtraSmallRow ? 0 : 3 }
    private var quantityLeadingPadding: CGFloat { isExtraSmallRow ? 5 : 8 }
    private var itemIconScale: Image.Scale { .large }
    private var nameFont: Font { FONT_NAME }
    private var quantityFont: Font { FONT_WEIGHT }
    private var limitedName: String {
        // 改行数で切ってから標準の末尾トランケートに任せる
        item.name.limitedByNewlines(maxLines: nameLineLimit)
    }
    private var limitedMemo: String {
        item.memo.limitedByNewlines(maxLines: memoLineLimit)
    }
    private var detailRowNeeded: Bool {
        // memo行か数量行を残す必要があるかを判定する
        if showMemo {
            return true
        }
        if showQuantityOnNameLine {
            return false
        }
        return true
    }

    
    init(item: M3Item,
         onEdit: @escaping (M3Item, CGPoint) -> Void) {
        self.item = item
        self.onEdit = onEdit
    }
    private var weightLabelText: String? {
        guard 0 < item.weight else { return nil }
        return "\(item.weight.decimalGrouped)\(weightUnit)"
    }
    private var quantityLabelText: String {
        "\(item.stock.decimalGrouped)/\(item.need.decimalGrouped)"
    }
    private var quantityCapsuleState: QuantityCapsuleState {
        guard 0 < item.need else { return 0 < item.stock ? .just : .over }
        if item.stock < item.need { return .under }
        return .just
    }


    var body: some View {
        HStack(spacing: 0) {
            // グループ縦線（透明スペース）
            Rectangle()
                .fill(.clear)
                .frame(width: 12)
                .padding(.leading, 0)
                .padding(.trailing, 8)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // アイテム・アイコン・チェック
                    Button {
                        item.check.toggle()
                        if item.check {
                            if linkCheckWithStock {
                                // チェックON時だけ在庫を必要数へ寄せる
                                item.stock = item.need
                            }
                        }else{
                            if linkCheckOffWithZero {
                                // チェックOFF時は明示的に在庫を0へ戻す
                                item.stock = 0
                            }
                        }
                    } label: {
                        Image(systemName
                              : item.check ? "checkmark.circle"     // Check ON
                              : item.need == 0 ? "circle.fill"      // Need = 0
                              : item.need <= item.stock ? "circle.circle"
                              : "circle")
                        .imageScale(itemIconScale)
                        .tint(item.need == 0 ? .secondary : .accentColor)
                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.top, checkTopPadding)
                    .padding(.bottom, checkBottomPadding)// タップ範囲を広げるため
                    .padding(.leading, 0)
                    .padding(.trailing, checkTrailingPadding)
                    // 名称
                    Group {
                        if item.name.isEmpty {
                            Text("new.item")
                        }else{
                            Text(verbatim: limitedName)
                        }
                    }
                    .font(nameFont)
                    .multilineTextAlignment(.leading)
                    // 指定行数まで折り返し、それ以上は末尾トランケートに任せる
                    .lineLimit(nameLineLimit, reservesSpace: false)
                    .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                    Spacer()
                    // 最小表示時は数量カプセルをname行の右端へ寄せる
                    if showQuantityOnNameLine {
                        quantityButton()
                            .padding(.leading, quantityLeadingPadding)
                    }
                }

                if detailRowNeeded {
                    HStack(spacing: 0) {
                        // インデント
                        Rectangle()
                            .frame(width: 30, height: 1)
                            .foregroundStyle(.clear)

                        // 数量編集（最小以外は2段目に配置）
                        if !showQuantityOnNameLine {
                            quantityButton()
                        }

                        // メモ
                        if showMemo {
                            if isBeginnerMode, item.name.isEmpty, item.memo.isEmpty {
                                Text("items.things.smallest.pieces")
                                    .font(FONT_MEMO)
                                    // 改行で行数を切り、lineLimitで末尾トランケートする
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(memoLineLimit)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                            }else{
                                Text(verbatim: limitedMemo)
                                    .font(FONT_MEMO)
                                    .multilineTextAlignment(.leading)
                                    // 改行を優先して指定行数に収め、超過はlineLimitに任せる
                                    .lineLimit(memoLineLimit, reservesSpace: false)
                                    .foregroundStyle(COLOR_MEMO)
                                    .padding(.leading, 4)
                            }
                        }
                        Spacer()
                    }
                }

                if DEBUG_SHOW_ORDER_ID {
                    Text("item (\(item.order)) [\(item.id)]")
                }
            }
            .padding(.vertical, contentVerticalPadding)
        }
        .frame(minHeight: itemRowHeight)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))// List標準余白を無くす
        .padding(.leading, 0)
        .transition(.move(edge: .top).combined(with: .opacity))
        //.contentShape(Rectangle()) // 全体をタップ可能領域にする
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
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
                .ignoresSafeArea(edges: .horizontal)
                .padding(.leading, 50)
                .padding(.trailing, 30)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { // 左スワイプ・アクション（フルスワイプ即削除を無効化）
            // アイテム削除（必ずボタンタップを挟み、誤操作を防ぐ）
            Button {
                item.delete()
            } label: {
                Label("delete", systemImage: "trash")
            }
            .tint(.orange)
            .disabled(item.parent == nil)
            // アイテム複製
            Button {
                item.duplicate()
            } label: {
                Label("copy", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
        }
    }

}

private extension ItemRowView {
    /// 数量カプセルを1か所にまとめる
    @ViewBuilder
    func quantityButton() -> some View {
        Button {
            // 行全体のフレーム中心を渡してポップアップ位置を決める
            guard let rf = rowFrame else { return }
            let po = CGPoint(x: rf.width / 2.0,
                             y: rf.minY)
            onEdit(item, po)
        } label: {
            HStack(spacing: 4) {
                if let weightLabelText {
                    infoCapsule(weightLabelText, state: quantityCapsuleState)
                }
                infoCapsule(quantityLabelText, state: quantityCapsuleState)
            }
            // カプセル間の隙間も含め、少し広めに数量編集のタップ対象にする
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BorderlessButtonStyle())
    }

    @ViewBuilder
    func infoCapsule(_ text: String, state: QuantityCapsuleState) -> some View {
        compactSlashText(text)
            .font(quantityFont)
            .foregroundStyle(state.foregroundStyle)
            .padding(.horizontal, quantityHorizontalPadding)
            .padding(.vertical, quantityVerticalPadding)
            .background(
                Capsule()
                    .fill(state.backgroundStyle(defaultColor: COLOR_ROW_GROUP))
            )
    }

    @ViewBuilder
    func compactSlashText(_ text: String) -> some View {
        if let slashIndex = text.firstIndex(of: "/") {
            let left = String(text[..<slashIndex])
            let right = String(text[text.index(after: slashIndex)...])
            HStack(spacing: 1) {
                Text(verbatim: left)
                Text(verbatim: "/")
                Text(verbatim: right)
            }
        } else {
            Text(verbatim: text)
        }
    }
}
