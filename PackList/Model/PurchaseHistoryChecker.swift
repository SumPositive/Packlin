import Foundation
import StoreKit

/// StoreKitの購入履歴を手早く確認するためのヘルパー
/// - Note: UI側で認証可否や広告特典の対象者判定に使い回せるよう、共通の静的メソッドとしてまとめる
struct PurchaseHistoryChecker {
    /// AI利用券を1度でも購入したことがあるかどうかを調べる
    /// - Returns: どれかのプロダクトIDでトランザクションが見つかった場合はtrue
    static func hasPurchasedOnce() async -> Bool {
        for option in AZUKI_CREDIT_PURCHASE_OPTIONS {
            for productId in option.allProductIds {
                if Task.isCancelled {
                    return false
                }
                if await Transaction.latest(for: productId) != nil {
                    return true
                }
            }
        }
        return false
    }
}
