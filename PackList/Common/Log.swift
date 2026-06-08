//
//  Log.swift
//  Calc26
//
//  Created by sumpo/azukid on 2025/07/07.
//

import Foundation
import FirebaseAnalytics
import FirebaseCore

/// Firebaseが初期化済みかを確認するヘルパー
private func isFirebaseConfigured() -> Bool {
    // FirebaseAppが登録済みなら初期化済みとみなす
    return FirebaseApp.app() != nil
}


enum LogLevel: Int, Comparable {
    case info = 0
    case debug = 1
    case warning = 2
    case error = 3
    case fatal = 4
    
    var prefix: String {
        switch self {
            case .info:    return "(i)"
            case .debug:   return "(d)"
            case .warning: return "(W)"
            case .error:   return "[ERROR]"
            case .fatal:   return "[FATAL]"
        }
    }
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

#if DEBUG
let currentLogLevel: LogLevel = .info
#else
let currentLogLevel: LogLevel = .error
#endif

func log(_ level: LogLevel,
         _ message: String,
         file: String = #file,
         line: Int = #line,
         function: String = #function)
{
    guard currentLogLevel <= level else { return }
    
    let fileName = (file as NSString).lastPathComponent
    let printOut = "\(fileName)(\(line)) \(function) \(level.prefix) \(message)"
    print(printOut)
    
    switch level {
        case .error, .fatal:
            // Firebase未初期化の場合はAnalytics送信を行わない
            if isFirebaseConfigured() {
                Analytics.logEvent("error_occured", parameters: [
                    "error_domain": function,
                    "error_code": -1,
                    "error_message": printOut
                ])
            }
        default:
            break
    }
}

/// Errorの内容をAnalyticsへ送信し、通常ログにも残す
func logError(_ error: Error,
              domain: String,
              message: String,
              file: String = #file,
              line: Int = #line,
              function: String = #function)
{
    let nsError = error as NSError
    let detail = "\(message): \(nsError.domain)(\(nsError.code)) \(nsError.localizedDescription)"
    let fileName = (file as NSString).lastPathComponent
    let printOut = "\(fileName)(\(line)) \(function) \(LogLevel.error.prefix) \(detail)"
    if currentLogLevel <= .error {
        print(printOut)
    }
    GALogger.log(.error_occured(domain: domain,
                                code: nsError.code,
                                message: printOut))
}

enum GAEvent {
    case app_launch
    case function(name: String, option: String)
    case settings_snapshot(settings: AnalyticsSettingsSnapshot)
    case setting_changed(key: String, value: String)
    case feature_use(name: String, source: String, detail: String?)
    case operation(name: String, target: String, source: String, detail: String?, count: Int?)
    case packlin_request(source: String, requirementLength: Int, hasBasePack: Bool, generatedItemsCount: Int)
    case pack_generated(source: String, itemsCount: Int)
    case purchase(productId: String, price: Double, currency: String)
    case credit_balance(remaining: Int)
    case error_occured(domain: String, code: Int, message: String?)
    /// API呼び出しの成否を集計するためのイベント
    case api_result(name: String, method: String, isSuccess: Bool, statusCode: Int?, errorDomain: String?, errorCode: String?, message: String?, retryCount: Int)
    /// チャッピー送信の結果を観測するイベント
    case chappy_send_result(source: String, isSuccess: Bool, requestTokens: Int?, responseTokens: Int?, errorDomain: String?, errorCode: String?, message: String?)
    /// AI利用券の購入検証の状況を観測するイベント
    case purchase_verify_result(status: String, isSuccess: Bool, productId: String, transactionId: String, balance: Int?, duplicate: Bool?, errorDomain: String?, errorCode: String?, message: String?)
    case screen_view(name: String) // SwiftUI手動トラッキング用
}

/// 匿名Analyticsへ送る設定値のスナップショット
struct AnalyticsSettingsSnapshot {
    let insertionPosition: String
    let showNeedWeight: Bool
    let weightDisplayInKg: Bool
    let linkCheckWithStock: Bool
    let linkCheckOffWithZero: Bool
    let displayMode: String
    let appearanceMode: String
    let fontScale: String
    let rowTextLines: String
    let autoItemReorder: Bool
    let dialStyle: String
    let hasCustomDialTuning: Bool

    static func current(userDefaults: UserDefaults = .standard) -> AnalyticsSettingsSnapshot {
        // AppStorageの初期値は未保存時にUserDefaultsへ存在しないため、Configの既定値で補完する
        AnalyticsSettingsSnapshot(
            insertionPosition: userDefaults.string(forKey: AppStorageKey.insertionPosition) ?? InsertionPosition.default.rawValue,
            showNeedWeight: userDefaults.boolValue(forKey: AppStorageKey.showNeedWeight, default: DEF_showNeedWeight),
            weightDisplayInKg: userDefaults.boolValue(forKey: AppStorageKey.weightDisplayInKg, default: DEF_weightDisplayInKg),
            linkCheckWithStock: userDefaults.boolValue(forKey: AppStorageKey.linkCheckWithStock, default: DEF_linkCheckWithStock),
            linkCheckOffWithZero: userDefaults.boolValue(forKey: AppStorageKey.linkCheckOffWithZero, default: DEF_linkCheckOffWithZero),
            displayMode: userDefaults.string(forKey: AppStorageKey.displayMode) ?? DisplayMode.default.rawValue,
            appearanceMode: userDefaults.string(forKey: AppStorageKey.appearanceMode) ?? AppearanceMode.default.rawValue,
            fontScale: userDefaults.string(forKey: AppStorageKey.fontScale) ?? FontScale.default.rawValue,
            rowTextLines: userDefaults.string(forKey: AppStorageKey.rowTextLines) ?? RowTextLines.default.rawValue,
            autoItemReorder: userDefaults.boolValue(forKey: AppStorageKey.autoItemReorder, default: DEF_autoItemReorder),
            dialStyle: userDefaults.string(forKey: AppStorageKey.dialStyle) ?? "shape",
            hasCustomDialTuning: userDefaults.data(forKey: AppStorageKey.dialTuning)?.isEmpty == false
        )
    }
}

private extension UserDefaults {
    func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        // 未保存時にfalse扱いにならないよう、存在確認してからboolを読む
        guard object(forKey: key) != nil else { return defaultValue }
        return bool(forKey: key)
    }
}

struct GALogger {
    static func log(_ event: GAEvent) {
        // Firebase未初期化時は警告ログを避ける
        if isFirebaseConfigured() == false {
            return
        }
        switch event {
            case .app_launch:
                Analytics.logEvent("app_launch", parameters: nil)
                
            case let .function(name, option):
                Analytics.logEvent("function", parameters: [
                    "name": name,
                    "option": option
                ])

            case let .settings_snapshot(settings):
                // 個人情報を含めず、利用設定の分布だけを集計する
                Analytics.logEvent("settings_snapshot", parameters: [
                    "insertion_position": settings.insertionPosition,
                    "show_need_weight": settings.showNeedWeight,
                    "weight_display_in_kg": settings.weightDisplayInKg,
                    "link_check_with_stock": settings.linkCheckWithStock,
                    "link_check_off_with_zero": settings.linkCheckOffWithZero,
                    "display_mode": settings.displayMode,
                    "appearance_mode": settings.appearanceMode,
                    "font_scale": settings.fontScale,
                    "row_text_lines": settings.rowTextLines,
                    "auto_item_reorder": settings.autoItemReorder,
                    "dial_style": settings.dialStyle,
                    "has_custom_dial_tuning": settings.hasCustomDialTuning
                ])

            case let .setting_changed(key, value):
                // 設定変更の発生頻度と変更後の値だけを集計する
                Analytics.logEvent("setting_changed", parameters: [
                    "setting_key": key,
                    "setting_value": value
                ])

            case let .feature_use(name, source, detail):
                // 機能単位の利用頻度を比較し、削減候補や改善対象を見つける
                Analytics.logEvent("feature_use", parameters: [
                    "feature_name": name,
                    "source": source,
                    "detail": detail ?? ""
                ])

            case let .operation(name, target, source, detail, count):
                // 操作パターンを集計し、手間の多い導線を見つける
                Analytics.logEvent("operation", parameters: [
                    "operation_name": name,
                    "target": target,
                    "source": source,
                    "detail": detail ?? "",
                    "count": count ?? -1
                ])

            case let .packlin_request(source, requirementLength, hasBasePack, generatedItemsCount):
                Analytics.logEvent("packlin_request", parameters: [
                    "source": source,
                    "requirement_length_bucket": requirementLengthBucket(requirementLength),
                    "has_base_pack": hasBasePack,
                    "generated_items_count": generatedItemsCount
                ])

            case let .pack_generated(source, itemsCount):
                Analytics.logEvent("pack_generated", parameters: [
                    "source": source,                // "user","ai","template" など
                    "items_count": itemsCount        // Int
                ])
                
            case let .purchase(productId, price, currency):
                Analytics.logEvent("purchase", parameters: [
                    "product_id": productId,
                    "value": price,                  // GA4汎用: 課金額などは value
                    "currency": currency            // "JPY" 等
                ])
                
            case let .credit_balance(remaining):
                Analytics.logEvent("credit_balance", parameters: [
                    "remaining": remaining
                ])
                
            case let .error_occured(domain, code, message):
                Analytics.logEvent("error_occured", parameters: [
                    "error_domain": domain,
                    "error_code": code,
                    "error_message": message ?? ""
                ])

            case let .api_result(name, method, isSuccess, statusCode, errorDomain, errorCode, message, retryCount):
                // API単位の成功・失敗を集計する
                Analytics.logEvent("api_result", parameters: [
                    "api_name": name,
                    "method": method,
                    "success": isSuccess,
                    "status_code": statusCode ?? -1,
                    "error_domain": errorDomain ?? "",
                    "error_code": errorCode ?? "",
                    "error_message": message ?? "",
                    "retry_count": retryCount
                ])

            case let .chappy_send_result(source, isSuccess, requestTokens, responseTokens, errorDomain, errorCode, message):
                // チャッピー送信が広告視聴か購入券かを含めて記録する
                Analytics.logEvent("chappy_send_result", parameters: [
                    "source": source,
                    "success": isSuccess,
                    "request_tokens": requestTokens ?? -1,
                    "response_tokens": responseTokens ?? -1,
                    "error_domain": errorDomain ?? "",
                    "error_code": errorCode ?? "",
                    "error_message": message ?? ""
                ])

            case let .purchase_verify_result(status, isSuccess, productId, transactionId, balance, duplicate, errorDomain, errorCode, message):
                // 購入検証の状態と成功/失敗を記録する
                Analytics.logEvent("purchase_verify_result", parameters: [
                    "status": status,
                    "success": isSuccess,
                    "product_id": productId,
                    "transaction_id": transactionId,
                    "balance": balance ?? -1,
                    "duplicate": duplicate ?? false,
                    "error_domain": errorDomain ?? "",
                    "error_code": errorCode ?? "",
                    "error_message": message ?? ""
                ])
                
            case let .screen_view(name):
                // GA4は自動スクリーン計測もあるが、SwiftUIは明示送信が安定
                Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                    AnalyticsParameterScreenName: name
                ])
        }
    }

    private static func requirementLengthBucket(_ count: Int) -> String {
        // 入力本文を送らず、改善分析に使える長さ区分だけを送る
        if count < 1 { return "empty" }
        if count < 50 { return "short" }
        if count < 200 { return "medium" }
        if count < 800 { return "long" }
        return "very_long"
    }
}
