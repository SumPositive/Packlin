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
let APPEND_AT_END_ROW_TOP_GAP: CGFloat = 20

/// 一覧の末尾にだけ表示する追加専用セル
/// 上下に APPEND_AT_END_ROW_VERTICAL_PADDING ぶんの余白を確保し、
/// アイコン・文字は垂直中央に揃える
struct AppendAtEndRowView: View {
    let systemImage: String
    let fontScale: FontScale
    var usesPackAddIcon = false
    var showsText = false
    /// 行の右端に添える表示（アイテム縦覧の合計重量など）。追加ボタンは中央のまま
    var trailingAccessory: AnyView? = nil
    /// 行の左端に添える操作（アイテム縦覧の「まとめて」など）。追加ボタンは中央のまま
    var leadingAccessory: AnyView? = nil
    let action: () -> Void

    private var hasAccessory: Bool { leadingAccessory != nil || trailingAccessory != nil }

    var body: some View {
        VStack(spacing: 0) {
            // 前行の誤タップを避けるため、追加ボタンの上に余白を置く
            Color.clear
                .frame(height: APPEND_AT_END_ROW_TOP_GAP)

            // 左右に添える表示があるときは横に並べ、重ならないようにする（追加ボタンは間の中央）
            HStack(spacing: 8) {
                if let leadingAccessory {
                    leadingAccessory
                        .fixedSize()
                }

                Spacer(minLength: 0)

                Button(action: action) {
                    // 下の余白・背景をまとめて付けるため Group で包む
                    Group {
                        if showsText {
                            // 初心者ヘルプの文字は折り返さない。幅が足りなければ、アイコンの下に小さく2行まで→アイコンだけ、の順に切り替える
                            // （左右に「まとめて」や合計重量が並ぶと、長い言語で1文字ずつ縦に崩れるため）
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    addIcon
                                    helpText
                                        .font(.footnote)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                VStack(spacing: 0) {
                                    addIcon
                                    helpText
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(maxWidth: 120)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                addIcon
                            }
                        } else {
                            addIcon
                        }
                    }
                    // アイコンと文字を含む左右40ptだけをタップ範囲にする（左右に添える表示があるときは詰める）
                    .padding(.horizontal, hasAccessory ? 16 : APPEND_AT_END_ROW_HORIZONTAL_TAP_PADDING)
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

                if let trailingAccessory {
                    trailingAccessory
                        .fixedSize()
                }
            }
            .padding(.horizontal, hasAccessory ? 8 : 0)

            // 上の余白（誤タップ防止ギャップ）と釣り合わせ、ボタンをセルの縦中央に置く
            Color.clear
                .frame(height: APPEND_AT_END_ROW_TOP_GAP)
        }
        .background(COLOR_ROW_BACK)
        .overlay(alignment: .bottom) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
        }
    }

    /// 初心者モードで追加ボタンに添える文字
    private var helpText: some View {
        Text("append.to.end")
            .foregroundStyle(COLOR_ADD_ACTION)
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
