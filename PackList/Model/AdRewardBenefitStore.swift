//
//  AdRewardBenefitStore.swift
//  PackList
//
//  Created by ChatGPT on 2025/...
//

import Foundation

/// 広告収益が設定金額を超えたときに付与する「AI1回無料特典」を管理するObservableObject
/// - Note: サーバーを介さずローカルだけで完結させるため、UserDefaultsへ永続化して再起動後も残す
@MainActor
final class AdRewardBenefitStore: ObservableObject {
    /// 利用可能な無料特典の残数
    @Published private(set) var availableBonusUsages: Int
    /// 最後に条件を満たした収益額（円換算が取れた場合のみ記録する）
    @Published private(set) var lastQualifiedRevenueYen: Double?

    private let userDefaults: UserDefaults
    private let bonusKey = "ad.reward.bonus.remaining"
    private let lastRevenueKey = "ad.reward.bonus.lastRevenueYen"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedBonus = userDefaults.integer(forKey: bonusKey)
        // 初期値は0だが、保存値があればそれを優先する
        self.availableBonusUsages = storedBonus
        if userDefaults.object(forKey: lastRevenueKey) != nil {
            self.lastQualifiedRevenueYen = userDefaults.double(forKey: lastRevenueKey)
        } else {
            self.lastQualifiedRevenueYen = nil
        }
    }

    /// 広告の収益が閾値を超えていれば無料特典を1回分付与する
    /// - Parameters:
    ///   - revenueYen: 円換算の収益額
    ///   - revenueUsd: 米ドル換算の収益額
    /// - Returns: 付与に成功した場合はtrue
    @discardableResult
    func grantBonusIfQualified(revenueYen: Double?, revenueUsd: Double?) -> Bool {
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
            return false
        }
        availableBonusUsages += 1
        persist()
        return true
    }

    /// 利用可能な無料特典を消費する。残数が無い場合はfalseを返す
    /// - Returns: 消費できたらtrue
    func consumeBonusIfAvailable() -> Bool {
        if availableBonusUsages < 1 {
            return false
        }
        availableBonusUsages -= 1
        persist()
        return true
    }

    /// 直前に消費した特典を復元したい場合に呼び出す
    func restoreConsumedBonus() {
        availableBonusUsages += 1
        persist()
    }

    /// 無料特典を保有しているかどうかを判定する
    var hasBonus: Bool {
        return 0 < availableBonusUsages
    }

    private func persist() {
        userDefaults.set(availableBonusUsages, forKey: bonusKey)
        if let lastQualifiedRevenueYen {
            userDefaults.set(lastQualifiedRevenueYen, forKey: lastRevenueKey)
        } else {
            userDefaults.removeObject(forKey: lastRevenueKey)
        }
    }
}
