//
//  CreditStore.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import Foundation
import Combine

/// ChatGPT生成で使用するクレジットの残高を管理するObservableObject
/// UserDefaultsに保存してアプリ再起動後も継続利用できるようにする
@MainActor
final class CreditStore: ObservableObject {
    @Published private(set) var credits: Int

    private let userDefaults: UserDefaults
    private let storageKey = "azuki.credit.balance"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedValue = userDefaults.integer(forKey: storageKey)
        // UserDefaults.integerは未設定時に0を返すため、そのまま利用
        self.credits = storedValue
    }

    /// クレジットを追加する
    func add(credits amount: Int) {
        // 負値が来ても安全なように上限チェックを行う（0未満なら何もしない）
        if amount < 1 {
            return
        }
        credits += amount
        persist()
    }

    /// 指定数だけクレジットを消費する
    func consume(credits amount: Int) throws {
        if amount < 1 {
            return
        }
        if credits < amount {
            throw AzukiAPIError.insufficientCredits
        }
        credits -= amount
        persist()
    }

    /// 現在の残高を初期化したい場合用
    func reset() {
        credits = 0
        persist()
    }

    private func persist() {
        userDefaults.set(credits, forKey: storageKey)
    }
}
