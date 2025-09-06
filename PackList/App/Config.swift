//
//  Config.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftUICore


// MARK: - Global let value
// 全モジュールで参照される固定値(let) （#define 同様の使い方）


//-------------------------------------- Layout関係
// CalcRollView 幅
let APP_WIDTH_MIN : CGFloat = 320      // 最小（SEの幅、全機能が見切れず使用できる状態）
let APP_WIDTH_MAX : CGFloat = 9999     // Free
// CalcRollView 高さ
let APP_HEIGHT_MIN : CGFloat = 150     // 最小（入力行と履歴1行が見える）
let APP_HEIGHT_MAX : CGFloat = 9999    // Free


//-------------------------------------- MAX関係

let APP_MAX_TITLE_ROWS : Int = 50
let APP_MAX_GROUP_ROWS : Int = 50
let APP_MAX_ITEM_ROWS : Int  = 100

let APP_MAX_NAME_LEN : Int = 50
let APP_MAX_MEMO_LEN : Int = 50

let APP_MAX_WEIGHT_NUM : Int = 999999
let APP_MAX_STOCK_NUM : Int  = 999
let APP_MAX_NEED_NUM : Int   = 999


//-------------------------------------- Color関係

let COLOR_TITLE: Color = .secondary         // App Name
//
//let COLOR_CALC_ACTIVE: Color = .accentColor // Calc活性枠
//let COLOR_CALC_INACTIVE: Color = .secondary // Calc非活性枠
//let COLOR_NUMBER: Color = .primary          // 数値
//let COLOR_ANSWER: Color = .accentColor      // 答え
//let COLOR_OPERATOR: Color = .cyan           // 演算子
//let COLOR_OPERATOR_WAIT: Color = .gray      // 待機演算子　右端の[.]や[)]
//let COLOR_UNIT: Color = .secondary          // 単位
//let COLOR_MEMO: Color = .purple             // メモ
//let COLOR_WARN: Color = .red                // 危険！警告色
//// 背景色
//let COLOR_BACK_FORMULA: Color = Color(.systemGray6)  // FormulaView
//let COLOR_BACK_SETTING: Color = Color(.systemGray4)  // SettingView


let COLOR_NAME: Color = .primary
let COLOR_NOTE: Color = .secondary
let COLOR_WEIGHT: Color = .secondary

//-------------------------------------- Font関係
let FONT_NAME: Font = .title3
let FONT_NOTE: Font = .headline
let FONT_WEIGHT: Font = .headline




// Setting 初期値

