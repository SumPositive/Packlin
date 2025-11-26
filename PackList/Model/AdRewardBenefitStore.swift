//
//  AdRewardBenefitStore.swift
//  PackList
//
//  Created by ChatGPT on 2025/...
//

import Foundation

/// 広告収益が設定金額を超えたときにAI利用券を追加する進捗を管理するObservableObject
/// - Note: サーバー連携とは独立してローカルで収益の積み上げを記録し、閾値を超えた回数だけ付与判定を行う
@MainActor
final class AdRewardBenefitStore: ObservableObject {
    /// 最後に特典が発生した日時
    @Published private(set) var lastGrantedAt: Date?
    /// 最後に条件を満たした収益額（円換算が取れた場合のみ記録する）
    @Published private(set) var lastQualifiedRevenueYen: Double?
    /// 付与までの進捗を把握するための累計収益（円）
    @Published private(set) var accumulatedRevenueYen: Double
    /// 付与までの進捗を把握するための累計収益（ドル）
    @Published private(set) var accumulatedRevenueUsd: Double

    private let userDefaults: UserDefaults
    private let lastGrantedKey = "ad.reward.bonus.lastGrantedAt"
    private let lastRevenueKey = "ad.reward.bonus.lastRevenueYen"
    private let accumulatedYenKey = "ad.reward.bonus.accumulatedYen"
    private let accumulatedUsdKey = "ad.reward.bonus.accumulatedUsd"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let grantedDate = userDefaults.object(forKey: lastGrantedKey) as? Date {
            self.lastGrantedAt = grantedDate
        } else {
            self.lastGrantedAt = nil
        }
        if userDefaults.object(forKey: lastRevenueKey) != nil {
            self.lastQualifiedRevenueYen = userDefaults.double(forKey: lastRevenueKey)
        } else {
            self.lastQualifiedRevenueYen = nil
        }
        // 累計収益も保存値を優先する。端数が多くなると視認性が下がるため、小数第2位で丸めてから表示する
        let storedYen = userDefaults.double(forKey: accumulatedYenKey)
        self.accumulatedRevenueYen = (storedYen * 100).rounded() / 100
        let storedUsd = userDefaults.double(forKey: accumulatedUsdKey)
        self.accumulatedRevenueUsd = (storedUsd * 100).rounded() / 100
    }

    /// 収益イベントを受け取り、必要に応じてAI利用券を付与する
    /// - Parameters:
    ///   - micros: 広告SDKから通知されるマイクロ単位の収益
    ///   - currencyCode: 通貨コード（例: "JPY" / "USD"）。判別できない場合はnil
    ///   - hasPurchaseHistory: StoreKit購入履歴が1件以上あるかどうか
    /// - Returns: 今回の視聴で追加できたAI利用券の枚数
    @discardableResult
    func recordRevenue(micros: Int64, currencyCode: String?, hasPurchaseHistory: Bool) -> Int {
        // 0や負の値が来ることは想定していないが、念のため無視する
        if micros < 1 {
            return 0
        }
        guard let upperCurrency = currencyCode?.uppercased() else {
            return 0
        }
        // 購入履歴が無い場合は広告収益の累積を進めない。購入後に改めてカウントしてもらう
        if hasPurchaseHistory == false {
            return 0
        }
        // マイクロ単位（100万分の1）から大きい単位へ直す
        let majorValue = Double(micros) / 1_000_000

        var grantedTickets = 0
        if upperCurrency == "JPY" {
            accumulatedRevenueYen += majorValue
            grantedTickets = grantBonusIfQualified(revenueYen: accumulatedRevenueYen, revenueUsd: nil)
            // 通貨を跨いだ二重カウントを避けるため、別通貨の進捗はリセットする
            if 0 < grantedTickets {
                lastGrantedAt = Date()
                accumulatedRevenueYen = normalizeProgress(accumulatedRevenueYen, threshold: AD_REWARD_THRESHOLD_YEN)
                accumulatedRevenueUsd = 0
            }
        } else if upperCurrency == "USD" {
            accumulatedRevenueUsd += majorValue
            grantedTickets = grantBonusIfQualified(revenueYen: nil, revenueUsd: accumulatedRevenueUsd)
            if 0 < grantedTickets {
                lastGrantedAt = Date()
                accumulatedRevenueUsd = normalizeProgress(accumulatedRevenueUsd, threshold: AD_REWARD_THRESHOLD_USD)
                accumulatedRevenueYen = 0
            }
        }

        persist()
        return grantedTickets
    }

    /// 広告の収益が閾値を超えていればAI利用券を付与する
    /// - Parameters:
    ///   - revenueYen: 円換算の収益額
    ///   - revenueUsd: 米ドル換算の収益額
    /// - Returns: 付与できたAI利用券枚数
    @discardableResult
    func grantBonusIfQualified(revenueYen: Double?, revenueUsd: Double?) -> Int {
        var reached = false
        if let yen = revenueYen {
            if AD_REWARD_THRESHOLD_YEN <= yen {
                reached = true
                lastQualifiedRevenueYen = yen
            }
        }
        if reached == false, let usd = revenueUsd {
            if AD_REWARD_THRESHOLD_USD <= usd {
                reached = true
                // 円換算が無い場合でも基準を満たしたことが分かるように直近値を保持する
                lastQualifiedRevenueYen = nil
            }
        }
        if reached == false {
            return 0
        }
        // 閾値を超えた回数分だけAI利用券を追加できるようにする
        var grantedTickets = 0
        if let yenRevenue = revenueYen {
            while AD_REWARD_THRESHOLD_YEN <= yenRevenue - (Double(grantedTickets) * AD_REWARD_THRESHOLD_YEN) {
                grantedTickets += 1
            }
        } else if let usdRevenue = revenueUsd {
            while AD_REWARD_THRESHOLD_USD <= usdRevenue - (Double(grantedTickets) * AD_REWARD_THRESHOLD_USD) {
                grantedTickets += 1
            }
        }
        return grantedTickets
    }

    /// 次の特典までに必要な金額を円ベースで返す（円の累計が有効なときのみ）
    var remainingYenToNextGrant: Double? {
        if accumulatedRevenueYen <= 0 {
            return AD_REWARD_THRESHOLD_YEN
        }
        let remaining = AD_REWARD_THRESHOLD_YEN - accumulatedRevenueYen
        if remaining <= 0 {
            return 0
        }
        return (remaining * 100).rounded() / 100
    }

    private func persist() {
        if let grantedDate = lastGrantedAt {
            userDefaults.set(grantedDate, forKey: lastGrantedKey)
        } else {
            userDefaults.removeObject(forKey: lastGrantedKey)
        }
        if let lastQualifiedRevenueYen {
            userDefaults.set(lastQualifiedRevenueYen, forKey: lastRevenueKey)
        } else {
            userDefaults.removeObject(forKey: lastRevenueKey)
        }
        userDefaults.set(accumulatedRevenueYen, forKey: accumulatedYenKey)
        userDefaults.set(accumulatedRevenueUsd, forKey: accumulatedUsdKey)
    }

    /// 累積の小数点以下が増えすぎないよう正規化して返す
    private func normalizeProgress(_ value: Double, threshold: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: threshold)
        return (remainder * 100).rounded() / 100
    }
}
