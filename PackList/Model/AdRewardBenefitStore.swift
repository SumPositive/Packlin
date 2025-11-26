//
//  AdRewardBenefitStore.swift
//  PackList
//
//  Created by ChatGPT on 2025/...
//

import Foundation

/// 広告収益が設定金額を超えたときに付与する「特典1回無料」を管理するObservableObject
/// - Note: サーバーを介さずローカルだけで完結させるため、UserDefaultsへ永続化して再起動後も残す
@MainActor
final class AdRewardBenefitStore: ObservableObject {
    /// 利用可能な特典1回無料の残数
    @Published private(set) var availableBonusUsages: Int
    /// 最後に条件を満たした収益額（円換算が取れた場合のみ記録する）
    @Published private(set) var lastQualifiedRevenueYen: Double?
    /// 付与までの進捗を把握するための累計収益（円）
    @Published private(set) var accumulatedRevenueYen: Double
    /// 付与までの進捗を把握するための累計収益（ドル）
    @Published private(set) var accumulatedRevenueUsd: Double

    private let userDefaults: UserDefaults
    /// 特典1回無料を溜め込まず、常に「1回使ってから次を受け取る」運用にするための上限値
    private let maxBonusCount = 1
    private let bonusKey = "ad.reward.bonus.remaining"
    private let lastRevenueKey = "ad.reward.bonus.lastRevenueYen"
    private let accumulatedYenKey = "ad.reward.bonus.accumulatedYen"
    private let accumulatedUsdKey = "ad.reward.bonus.accumulatedUsd"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // 旧バージョンで2回以上保有していたとしても、今回からは1回に丸める
        let storedBonus = min(userDefaults.integer(forKey: bonusKey), maxBonusCount)
        // 初期値は0だが、保存値があればそれを優先する
        self.availableBonusUsages = storedBonus
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

    /// 収益イベントを受け取り、必要に応じて特典1回無料を付与する
    /// - Parameters:
    ///   - micros: 広告SDKから通知されるマイクロ単位の収益
    ///   - currencyCode: 通貨コード（例: "JPY" / "USD"）。判別できない場合はnil
    /// - Returns: 特典付与に成功したらtrue
    @discardableResult
    func recordRevenue(micros: Int64, currencyCode: String?) -> Bool {
        // 0や負の値が来ることは想定していないが、念のため無視する
        if micros < 1 {
            return false
        }
        guard let upperCurrency = currencyCode?.uppercased() else {
            return false
        }
        // すでに「特典1回無料」を保有している間はカウントを進めず、使い切ってから次のサイクルを開始する
        if maxBonusCount <= availableBonusUsages {
            return false
        }
        // マイクロ単位（100万分の1）から大きい単位へ直す
        let majorValue = Double(micros) / 1_000_000

        var granted = false
        if upperCurrency == "JPY" {
            accumulatedRevenueYen += majorValue
            granted = grantBonusIfQualified(revenueYen: accumulatedRevenueYen, revenueUsd: nil)
            // 特典付与に成功したら累計をゼロに戻し、「使い切り」であることを明確にする
            if granted {
                accumulatedRevenueYen = 0
                accumulatedRevenueUsd = 0
            }
        } else if upperCurrency == "USD" {
            accumulatedRevenueUsd += majorValue
            granted = grantBonusIfQualified(revenueYen: nil, revenueUsd: accumulatedRevenueUsd)
            if granted {
                accumulatedRevenueUsd = 0
                accumulatedRevenueYen = 0
            }
        }

        persist()
        return granted
    }

    /// 広告の収益が閾値を超えていれば特典1回無料を付与する
    /// - Parameters:
    ///   - revenueYen: 円換算の収益額
    ///   - revenueUsd: 米ドル換算の収益額
    /// - Returns: 付与に成功した場合はtrue
    @discardableResult
    func grantBonusIfQualified(revenueYen: Double?, revenueUsd: Double?) -> Bool {
        // すでに上限まで保有していれば新規付与はスキップし、広告を使う動機を保つ
        if maxBonusCount <= availableBonusUsages {
            return false
        }

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

    /// 利用可能な特典1回無料を消費する。残数が無い場合はfalseを返す
    /// - Returns: 消費できたらtrue
    func consumeBonusIfAvailable() -> Bool {
        if availableBonusUsages < 1 {
            return false
        }
        availableBonusUsages -= 1
        // 「使い切り」を明確にするため、使用したタイミングで進捗もリセットして次のカウントをゼロから始める
        accumulatedRevenueYen = 0
        accumulatedRevenueUsd = 0
        persist()
        return true
    }

    /// 直前に消費した特典を復元したい場合に呼び出す
    func restoreConsumedBonus() {
        // 取り消し操作などで1回分だけ復元する。上限を超えないように抑制する
        availableBonusUsages = min(availableBonusUsages + 1, maxBonusCount)
        persist()
    }

    /// 特典1回無料を保有しているかどうかを判定する
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
        userDefaults.set(accumulatedRevenueYen, forKey: accumulatedYenKey)
        userDefaults.set(accumulatedRevenueUsd, forKey: accumulatedUsdKey)
    }
}
