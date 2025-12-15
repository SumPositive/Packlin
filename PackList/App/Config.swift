//
//  Config.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers


// MARK: - Global let value
// 全モジュールで参照される固定値(let) （#define 同様の使い方）

//-------------------------------------- DEBUG
let DEBUG_SHOW_ORDER_ID = false

//-------------------------------------- アルゴリズム定数
let ORDER_SPARSE: Int = 1000 // スパース間隔（.orderをまばらにして挿入時に中間値を使い、全更新を減らす）

//-------------------------------------- Layout関係
// CalcRollView 幅
let APP_WIDTH_MIN : CGFloat = 320      // 最小（SEの幅、全機能が見切れず使用できる状態）
let APP_WIDTH_MAX : CGFloat = 9999     // Free
// CalcRollView 高さ
let APP_HEIGHT_MIN : CGFloat = 150     // 最小（入力行と履歴1行が見える）
let APP_HEIGHT_MAX : CGFloat = 9999    // Free

// 行の下線太さ
let LIST_SEPARATOR_THICKNESS: CGFloat = 0.8 // List区切り線の太さ
// ヘッダーの高さ
let APP_HEADER_HEIGHT_BEG : CGFloat = 100.0  // 初心者モード
let APP_HEADER_HEIGHT_EXP : CGFloat =  56.0  // 達人モード
// iPadのマルチウィンドウ時に左上のシステムボタンとヘッダーが重ならないようにする余白
let IPAD_WINDOW_CONTROL_INSET : CGFloat = 64.0

//-------------------------------------- MAX関係

let APP_MAX_PACK_ROWS : Int = 30
let APP_MAX_PART_ROWS : Int = 30
let APP_MAX_ITEM_ROWS : Int = 100

let APP_MAX_NAME_LEN : Int = 200     // .name 文字数
let APP_MAX_MEMO_LEN : Int = 200     // .memo 文字数

let APP_MAX_WEIGHT_NUM : Int = 999999   // (g)
let APP_MAX_STOCK_NUM : Int  = 999      // 個数
let APP_MAX_NEED_NUM : Int   = 999      // 個数

// チャッピー(AI)
let AI_REQUIREMENT_MAX: Int = 1000     // 要望の最大文字数



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

// View背景
let COLOR_BACK_VIEW: Color = Color(.systemGroupedBackground)
// 文字や数字の入力部背景
let COLOR_BACK_INPUT: Color = Color(.systemBackground)
// Popupの背景、Viewより濃い
let COLOR_BACK_POPUP: Color = Color(.systemGray3)
// 行（セル）の背景
let COLOR_ROW_BACK: Color = Color(.systemBackground)
// グループセクション、カプセル色
let COLOR_ROW_GROUP: Color = Color(UIColor { traitCollection in
    if traitCollection.userInterfaceStyle == .dark {
        return .systemGray4
    } else {
        return .systemGray6
    }
})
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



//-------------------------------------- Setting 初期値

// 新規追加の位置
let DEF_insertionPosition: InsertionPosition = .head
// 必要重量を表示する
let DEF_showNeedWeight = true
// 重量計1000gからkg表示
let DEF_weightDisplayInKg = true
// チェックONで在庫数を満たす
let DEF_linkCheckWithStock = false
// チェックOFFで在庫数を0にする
let DEF_linkCheckOffWithZero = false
// ヘッダーの説明を表示するモード（初心者／上級者）
let DEF_displayMode: DisplayMode = .beginner
// 行の最大表示行数（name／memo）
let DEF_rowTextLines: RowTextLines = .threeLines
// 編集操作に応じて自動で並び替え　　Auto Reorder on Edit
let DEF_autoItemReorder = true

/// 不揮発保存する
enum AppStorageKey {
    // 新規追加の位置
    static let insertionPosition = "setting.insertionPosition"
    // 必要重量を表示する
    static let showNeedWeight = "setting.showNeedWeight"
    // 重量計1000gからkg表示
    static let weightDisplayInKg = "setting.weightDisplayInKg"
    // チェックONで在庫数を満たす
    static let linkCheckWithStock = "setting.linkCheckWithStock"
    // チェックOFFで在庫を0にする
    static let linkCheckOffWithZero = "setting.linkCheckOffWithZero"
    // 表示モード（初心者／上級者）
    static let displayMode = "setting.displayMode"
    // 行の表示行数（name／memo）
    static let rowTextLines = "setting.rowTextLines"
    // 編集操作に応じて自動で並び替え　　Auto Reorder on Edit
    static let autoItemReorder = "setting.autoItemReorder"
    // AI生成画面での要望テキスト（作成モード用）。モード別に保持して書きかけを分ける
    static let aiRequirementTextCreate = "aiCreate.requirementText.create"
    // AI生成画面での要望テキスト（修正モード用）。修正中の入力を作成モードと別枠で保存する
    static let aiRequirementTextEdit = "aiCreate.requirementText.edit"
    // 購入通知済みのトランザクションIDを永続化するためのキー（重複アラート抑止用）
    static let aiPurchaseNotifiedTransactionIds = "aiCreate.notifiedTransactions"
    // 広告視聴で付与される特典アイコンの個数を保持する
    static let aiAdRewardStamps = "aiCreate.adRewardStamps"
}

//-------------------------------------- パックJSON関係
let PACK_JSON_DTO_PRODUCT_NAME = "Packlin" // 生成ファイルの出自判定に利用
let PACK_JSON_DTO_COPYRIGHT = "2025_sumpo@azukid.com" // 差異あれば読み込みエラー
let PACK_JSON_DTO_VERSION   = "3.0" // マイグレーション用
let PACK_FILE_EXTENSION = "packlin" // 共有するファイルの拡張子
let PACK_FILE_UTTYPE = UTType(filenameExtension: PACK_FILE_EXTENSION) ?? .data // ファイルピッカーで使用

//-------------------------------------- azuki-api / OpenAI 関連
/// azuki-api のベースURL。実行時に403などが発生した場合はConfigで差し替える想定
#if DEBUG
//------------------------- DEBUGモード
// Local server
// ATS設定：App Transport Security Settings：Allow Arbitrary Loads=Yes
// ローカルサーバを起動する
//   % npx wrangler dev --local
// 実機接続するため ngrok により localhost を公開する
//   $ ngrok http 8787　　＜起動により表示された公開URLを下記へコピペする
let AZUKI_API_BASE_URL = URL(string: "https://muriel-chestnutty-unprecedentedly.ngrok-free.dev")!
#else
//------------------------- RELEASEモード（ArchiveでAppStoreにアップする）
// TestFlightでは、RELEASEモードで本番同様だが、購入はSandboxテストモードで動作するので課金されない！
// Cloudflare Workers & Pagesへデプロイする
//   % npx wrangler deploy
// 本番 Deploy server
let AZUKI_API_BASE_URL = URL(string: "https://azuki-api.azukid.com")!
#endif

/// 消費型クレジットの商品ID群（azuki-api側の環境変数：IAP_PRODUCT_CREDIT_MAP と一致させる）
/// - Note: 配信地域ごとにIDが異なるため、日本向けとその他地域向けで定数を分けて管理する
/// AI利用券の金額表示をLocaleに合わせて切り替えるための構造体
struct AzukiCreditPurchaseOption: Hashable {
    /// StoreKitの商品ID（日本向け）
    let productIdJapan: String
    /// StoreKitの商品ID（その他地域向け）
    let productIdGlobal: String
    /// 日本語表示向けの税込価格（円）
    let priceYen: Int
    /// 英語表示向けの税込価格（ドル）
    let priceUsd: Decimal
    /// 加算されるAI利用券の枚数
    let tickets: Int

    /// 端末のLocaleから実際に利用すべき商品IDを決定する
    /// - Parameter locale: 現在のLocale（地域と言語を判定する）
    /// - Returns: 日本なら日本向けID、それ以外なら海外向けID
    func productId(for locale: Locale) -> String {
        if isJapan(locale: locale) {
            return productIdJapan
        }
        return productIdGlobal
    }

    /// すべての地域向けIDを配列として返す（トランザクション再検証等で利用）
    var allProductIds: [String] {
        Array(Set([productIdJapan, productIdGlobal]))
    }

    /// 与えられた商品IDがこのオプションに該当するかを判定する
    /// - Parameter productId: StoreKitから返ってきた商品ID
    /// - Returns: 日本向けまたは海外向けIDのいずれかと一致すればtrue
    func contains(productId: String) -> Bool {
        if productId == productIdJapan {
            return true
        }
        return productId == productIdGlobal
    }

    /// アプリのLocaleに応じた価格文字列を返す
    /// - Parameter locale: SwiftUIから渡される現在のLocale
    /// - Returns: 「¥50」や「$0.50」のような通貨文字列
    func localizedPriceString(for locale: Locale) -> String {
        // 日本語のLocaleでは円表記にする
        if isJapan(locale: locale) {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.numberStyle = .currency
            formatter.currencyCode = "JPY"
            formatter.maximumFractionDigits = 0
            let number = NSNumber(value: priceYen)
            if let formatted = formatter.string(from: number) {
                return formatted
            }
            // フォーマット失敗時は簡易文字列へフォールバック
            return "¥\(priceYen)"
        }
        // その他の地域はドル表記
        // NumberFormatterでドル価格を2桁固定表示する
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = NSDecimalNumber(decimal: priceUsd)
        if let formatted = formatter.string(from: number) {
            return formatted
        }
        // フォーマットに失敗した場合は素直な文字列へフォールバック
        return "$\(number.stringValue)"
    }

    /// ロケールに応じたボタン表示文言を返す
    /// - Parameter locale: 文字列判定に利用するLocale
    /// - Returns: 日本語なら「5枚：¥50」、英語なら「Get 5 tickets: $0.50」など
    func localizedButtonTitle(for locale: Locale) -> String {
        let priceText = localizedPriceString(for: locale)
        if isJapan(locale: locale) {
            // 日本語環境では従来の表記を踏襲する
            return "\(tickets)枚：\(priceText)"
        }
        // 英語環境では「credits」を用いた案内に切り替える
        return "Get \(tickets) tickets: \(priceText)"
    }

    /// Localeの地域情報から日本かどうかを判定する
    /// - Parameter locale: 地域コードを含むLocale
    /// - Returns: 日本ならtrue、それ以外ならfalse
    private func isJapan(locale: Locale) -> Bool {
        if let regionCode = locale.region?.identifier.lowercased() {
            if regionCode == "jp" {
                return true
            }
        }
        // regionCodeが取得できないケースに備えてidentifierも確認する
        let identifier = locale.identifier.lowercased()
        if identifier.contains("_jp") || identifier.contains("-jp") {
            return true
        }
        return false
    }
}

/// 購入オプション定義      productIdは、App Store Connect アプリ内課金の「製品ID」
///  IDを変更や追加した場合、azuki-api側の環境変数 IAP_PRODUCT_CREDIT_MAP を更新すること
let AZUKI_CREDIT_PURCHASE_OPTIONS: [AzukiCreditPurchaseOption] = [
    AzukiCreditPurchaseOption(
        productIdJapan:  "AiTickets_1_JPY", // 日本：¥50 / +1枚
        productIdGlobal: "AiTickets_1_USD", // 他地域：$0.49 / +1tickets
        priceYen: 50,
        priceUsd: 0.49,
        tickets: 1
    ),
    AzukiCreditPurchaseOption(
        productIdJapan:  "AiTickets_5_JPY", // 日本：¥150 / +5枚
        productIdGlobal: "AiTickets_5_USD", // 他地域：$1.49 / +5tickets
        priceYen: 150,
        priceUsd: 1.49,
        tickets: 5
    ),
]
/// 1回の生成で消費するクレジット数。サーバー側と数値を合わせるため定数化
let CHATGPT_GENERATION_CREDIT_COST = 1

