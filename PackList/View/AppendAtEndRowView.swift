//
//  AppendAtEndRowView.swift
//  PackList
//
//  末尾追加セル用の共通ビュー
//

import SwiftUI

/// 末尾追加セルの上下余白。コンテンツに対してこの値ぶんの padding を上下に与え、
/// セル高さは padding を含めて内容に応じて自動調整される
let APPEND_AT_END_ROW_VERTICAL_PADDING: CGFloat = 8
let APPEND_AT_END_ROW_HORIZONTAL_TAP_PADDING: CGFloat = 40
let APPEND_AT_END_ROW_CAPSULE_VERTICAL_PADDING: CGFloat = 2
let APPEND_AT_END_ROW_TOP_GAP: CGFloat = 30

/// 一覧の末尾にだけ表示する追加専用セル
/// 上下に APPEND_AT_END_ROW_VERTICAL_PADDING ぶんの余白を確保し、
/// アイコン・文字は垂直中央に揃える
struct AppendAtEndRowView: View {
    let systemImage: String
    let fontScale: FontScale
    var usesPackAddIcon = false
    var showsText = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 前行の誤タップを避けるため、追加ボタンの上に余白を置く
            Color.clear
                .frame(height: APPEND_AT_END_ROW_TOP_GAP)

            HStack {
                Spacer(minLength: 0)

                Button(action: action) {
                    HStack(spacing: 8) {
                        addIcon

                        if showsText {
                            Text("append.to.end")
                                .font(.footnote)
                                .foregroundStyle(COLOR_ADD_ACTION)
                        }
                    }
                    // アイコンと文字を含む左右40ptだけをタップ範囲にする
                    .padding(.horizontal, APPEND_AT_END_ROW_HORIZONTAL_TAP_PADDING)
                    .padding(.vertical, APPEND_AT_END_ROW_CAPSULE_VERTICAL_PADDING)
                    .background(
                        Capsule()
                            .fill(COLOR_ADD_ACTION.opacity(0.05))
                    )
                    .padding(.vertical, APPEND_AT_END_ROW_VERTICAL_PADDING - APPEND_AT_END_ROW_CAPSULE_VERTICAL_PADDING)
                    .contentShape(Rectangle())
                    // List のセクションフッター等によりセルが垂直方向に引き伸ばされて
                    // コンテンツが下に寄るのを防ぐ：自然サイズに固定する
                    .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .background(COLOR_ROW_BACK)
        .overlay(alignment: .bottom) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
        }
    }

    @ViewBuilder
    private var addIcon: some View {
        if usesPackAddIcon {
            // パック追加はヘッダーと同じカバン＋プラスの合成アイコンにする
            ZStack {
                Image(systemName: "case")
                    .font(.system(size: 17, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .padding(.top, 3)
            }
            .foregroundStyle(COLOR_ADD_ACTION)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(COLOR_ADD_ACTION)
        }
    }
}
