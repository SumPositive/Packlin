//
//  Config.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI


// MARK: - Global let value
// 全モジュールで参照される固定値(let) （#define 同様の使い方）

//-------------------------------------- DEBUG
let DEBUG_SHOW_ORDER_ID = false


//-------------------------------------- JSON関係
let PACK_JSON_DTO_COPYRIGHT = "2025_sumpo@azukid.com" // 差異あれば読み込みエラー
let PACK_JSON_DTO_VERSION   = "3.0" // マイグレーション用

//-------------------------------------- Layout関係
// CalcRollView 幅
let APP_WIDTH_MIN : CGFloat = 320      // 最小（SEの幅、全機能が見切れず使用できる状態）
let APP_WIDTH_MAX : CGFloat = 9999     // Free
// CalcRollView 高さ
let APP_HEIGHT_MIN : CGFloat = 150     // 最小（入力行と履歴1行が見える）
let APP_HEIGHT_MAX : CGFloat = 9999    // Free

// 行の下線太さ
let LIST_SEPARATOR_THICKNESS: CGFloat = 0.8 // List区切り線の太さ

//-------------------------------------- MAX関係

let APP_MAX_PACK_ROWS : Int = 50
let APP_MAX_PART_ROWS : Int = 50
let APP_MAX_ITEM_ROWS : Int  = 100

let APP_MAX_NAME_LEN : Int = 200     // .name 文字数
let APP_MAX_MEMO_LEN : Int = 200     // .memo 文字数

let APP_MAX_WEIGHT_NUM : Int = 999999   // (g)
let APP_MAX_STOCK_NUM : Int  = 999      // 個数
let APP_MAX_NEED_NUM : Int   = 999      // 個数


//-------------------------------------- Color関係
//Color.primary        // テキスト用の主要カラー（ダーク/ライトで変化）
//Color.secondary      // 補助的なテキストカラー
//Color.accentColor    // アクセントカラー（アプリの強調色）
//Color.background     // 背景色
//Color.label          // テキストラベル用カラー
//Color.systemRed      // システムの赤色
//Color.systemBlue     // システムの青色
//Color.systemGray     // システムのグレー

// 文字表示色
let COLOR_TITLE: Color = .secondary         // App Name
let COLOR_NAME: Color = .primary
let COLOR_NAME_EMPTY: Color = .secondary
let COLOR_MEMO: Color = .primary
let COLOR_WEIGHT: Color = .primary

// 背景色
let COLOR_BACK_VIEW: Color = Color(.systemGroupedBackground)   // View背景
let COLOR_BACK_INPUT: Color = Color(.systemBackground)   // 文字や数字の入力部背景
let COLOR_BACK_POPUP: Color = Color(.systemGray3)       // Popupの背景、Viewより濃い


let COLOR_ROW_PACK: Color = Color(.systemBackground)
let COLOR_ROW_GROUP: Color = Color(.systemGray6)
let COLOR_ROW_ITEM: Color = Color(.systemBackground)
// 行の下線色
let COLOR_LIST_SEPARATOR: Color = Color(UIColor { traitCollection in
    if traitCollection.userInterfaceStyle == .dark {
        return UIColor(white: 1.0, alpha: 0.6)
    } else {
        return UIColor(white: 0.0, alpha: 0.3)
    }
})


//-------------------------------------- Font関係
//Text("タイトル").font(.largeTitle)
//Text("見出し").font(.title)
//Text("サブ見出し").font(.title2)
//Text("本文").font(.body)
//Text("キャプション").font(.caption)
//Text("脚注").font(.footnote)

let FONT_NAME: Font = .title2
let FONT_MEMO: Font = .body
let FONT_WEIGHT: Font = .body
let FONT_STOCK: Font = .title2

let FONT_EDIT: Font = .title2



// Setting 初期値

enum AppStorageKey {
    // 新規追加の位置
    static let insertionPosition = "setting.insertionPosition"
    static let showNeedWeight = "setting.showNeedWeight"
}

enum InsertionPosition: String, CaseIterable, Identifiable, Codable {
    // 選択肢
    case head
    case tail
    // 初期値
    static let `default`: InsertionPosition = .head

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .head:
            return "setting.insertion.head"
        case .tail:
            return "setting.insertion.tail"
        }
    }
}

