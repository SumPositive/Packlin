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
    // Textが行上限を越えた際に末尾のドットを出さず、超過分をクリップで隠すための高さ
    private var nameMaxHeight: CGFloat {
        CGFloat(nameLineLimit) * UIFont.preferredFont(forTextStyle: .title2).lineHeight
    }
    private var memoMaxHeight: CGFloat {
        CGFloat(memoLineLimit) * UIFont.preferredFont(forTextStyle: .body).lineHeight
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
    // 数量表示Text
    private var quantityLabelText: String {
        var text: String = ""
        if 0 < item.weight {
            // 個重量
            text = "\(item.weight.decimalGrouped)\(weightUnit)　"
        }
        // 在庫数／必要数
        text += "\(item.stock.decimalGrouped)／\(item.need.decimalGrouped)"
        return text
    }


    var body: some View {
        HStack(spacing: 0) {
            // グループ縦線
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
                        .imageScale(.large)
                        .tint(item.need == 0 ? .secondary : .accentColor)
                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.top, 8)
                    .padding(.bottom, 12)// タップ範囲を広げるため
                    .padding(.leading, 0)
                    .padding(.trailing, 8)
                    // 名称
                    item.name.placeholderText("新しいアイテム")
                        // 名前が長い場合でも折り返して全体を見せる
                        .font(FONT_NAME)
                        .frame(maxHeight: nameMaxHeight, alignment: .leading)
                        .clipped()
                        .foregroundStyle(isNamePlaceholder ? .secondary : COLOR_NAME)
                    Spacer()
                    // 最小表示時は数量カプセルをname行の右端へ寄せる
                    if showQuantityOnNameLine {
                        quantityButton()
                            .padding(.leading, 8)
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
                                Text("アイテムとは、持ち物そのもの。最小単位です")
                                    .font(FONT_MEMO)
                                    .frame(maxHeight: memoMaxHeight, alignment: .leading)
                                    .clipped()
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                            }else{
                                Text(item.memo)
                                    .font(FONT_MEMO)
                                    .frame(maxHeight: memoMaxHeight, alignment: .leading)
                                    .clipped()
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
            .padding(.vertical, 4)
        }
        .frame(minHeight: rowHeight)
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
                Label("削除", systemImage: "trash")
            }
            .tint(.orange)
            .disabled(item.parent == nil)
            // アイテム複製
            Button {
                item.duplicate()
            } label: {
                Label("複製", systemImage: "plus.square.on.square")
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
            // 数量表示
            Text(quantityLabelText)
                .font(FONT_WEIGHT)
                .foregroundStyle(COLOR_WEIGHT)
        }
        .buttonStyle(BorderlessButtonStyle())
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(COLOR_ROW_GROUP)
        )
    }
}

