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
        case .threeLines:
            return "3.lines"
        case .twoLines:
            return "2.lines"
        case .oneLine:
            return "1.line"
        case .minimal:
            return "min"
        case .extraSmall:
            return "tiny"
        }
    }

    /// name 部分の最大行数
    var nameLineLimit: Int {
        switch self {
        case .threeLines:
            return 3
        case .twoLines:
            return 2
        case .oneLine, .minimal, .extraSmall:
            return 1
        }
    }

    /// memo 部分の最大行数（0で非表示にする）
    var memoLineLimit: Int {
        switch self {
        case .threeLines:
            return 3
        case .twoLines:
            return 2
        case .oneLine:
            return 1
        case .minimal, .extraSmall:
            return 0
        }
    }

    /// 重量計や数量カプセルをname行に寄せるかどうか
    var placeAccessoryOnNameLine: Bool {
        self == .minimal || self == .extraSmall
    }

    /// アイテム行だけをさらに詰める極小表示かどうか
    var usesExtraSmallItemRow: Bool {
        self == .extraSmall
    }
}
