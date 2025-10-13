//
//  CreditStore.swift
//  PackList
//
//  Created by sumpo on 2025/10/12.
//

import Foundation
import Combine

/// ChatGPT生成で使用するクレジットの残高を管理するObservableObject
/// UserDefaultsに保存してアプリ再起動後も継続利用できるようにする
@MainActor
final class CreditStore: ObservableObject {
    @Published private(set) var credits: Int
    /// azuki-api側でユーザーを識別するためのID。アプリ初回起動時に作成して以後はUserDefaultsで保持する。
    let userId: String

    private let userDefaults: UserDefaults
    private let storageKey = "azuki.credit.balance"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.userId = AzukiUserIdentifier.loadOrCreate(userDefaults: userDefaults)
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

    /// サーバーから取得した残高で上書きしたい場合に使用する
    /// - Parameter amount: サーバーが返した最新残高
    func overwrite(credits amount: Int) {
        if amount < 0 {
            credits = 0
        } else {
            credits = amount
        }
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

/// azuki-apiがユーザーを一意に判定するためのIDを管理するヘルパ
private enum AzukiUserIdentifier {
    private static let storageKey = "azuki.api.userId"

    /// UserDefaultsに保存済みであればそれを返し、無ければ新たにUUIDを生成して保存する
    /// - Parameter userDefaults: 保存先となるUserDefaults
    /// - Returns: APIへ渡すuserId文字列
    static func loadOrCreate(userDefaults: UserDefaults) -> String {
        if let stored = userDefaults.string(forKey: storageKey), stored.isEmpty == false {
            return stored
        }
        let newId = UUID().uuidString.lowercased()
        userDefaults.set(newId, forKey: storageKey)
        return newId
    }
}
