//
//  RowTextLines.swift
//  PackList
//
//  Created by sumpo on 2025/09/25.
//

import SwiftUI

/// 行ごとの表示行数設定（name と memo の最大行数をまとめて管理する）
enum RowTextLines: String, CaseIterable, Identifiable, Codable {
    // 選択肢（rawValueは保存用）
    case threeLines = "three"
    case twoLines = "two"
    case oneLine = "one"
    case minimal = "mini"
    case extraSmall = "extraSmall"

    // デフォルト値（AppStorage初期化にも使う）
    static let `default`: RowTextLines = DEF_rowTextLines

    var id: String { rawValue }

    /// 設定画面での表示用ラベル
    var localizedKey: LocalizedStringKey {
        switch self {
        // 行数ではなく「何を出すか」で選ぶ名前にする（タグやメモが空なら、その行は出ないため）
        case .threeLines:
            return "row.lines.tags.memo"
        case .twoLines:
            return "row.lines.tags"
        case .oneLine:
            return "row.lines.basic"
        case .minimal:
            return "min"
        case .extraSmall:
            return "tiny"
        }
    }

    // MARK: 行の表示（1行目は常に「名称・重量（・数量）」。アイテム行・グループ行で共通）

    /// アイテム行の2行目にタグを出すか（タグ付き・タグ・メモ付き）
    var itemShowsTagLine: Bool {
        self == .twoLines || self == .threeLines
    }

    /// メモの行を出すか（タグ・メモ付き）。アイテム行は3行目、グループ行は2行目
    var itemShowsMemoLine: Bool {
        self == .threeLines
    }

    /// アイテム行だけをさらに詰める極小表示かどうか
    var usesExtraSmallItemRow: Bool {
        self == .extraSmall
    }
}
