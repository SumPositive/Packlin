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
    print("\(fileName)(\(line)) \(function) \(level.prefix) \(message)")
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
                
            case let .screen_view(name):
                // GA4は自動スクリーン計測もあるが、SwiftUIは明示送信が安定
                Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                    AnalyticsParameterScreenName: name
                ])
        }
    }
}

