//
//  Log.swift
//  Calc26
//
//  Created by sumpo/azukid on 2025/07/07.
//

import Foundation


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
            Analytics.logEvent("error_occured", parameters: [
                "error_domain": function,
                "error_code": -1,
                "error_message": printOut
            ])
        default:
            break
    }
}


import FirebaseAnalytics

enum GAEvent {
    case app_launch
    case function(name: String, option: String)
    case packlin_request(userId: String, requirement: String)
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

struct GALogger {
    static func log(_ event: GAEvent) {
        switch event {
            case .app_launch:
                Analytics.logEvent("app_launch", parameters: nil)
                
            case let .function(name, option):
                Analytics.logEvent("function", parameters: [
                    "name": name,
                    "option": option
                ])
                
            case let .packlin_request(userId, requirement):
                Analytics.logEvent("packlin_request", parameters: [
                    "userId": userId,
                    "requirement": requirement
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
}
