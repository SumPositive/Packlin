//
//  CreditStore.swift
//  PackList
//
//  Created by sumpo on 2025/10/12.
//

import Foundation
import Combine

/// ChatGPT生成で使用するクレジットの残高を管理するObservableObject
/// Keychainへ保存した値を即座に参照しつつ、サーバー側の残高と定期的に同期できるようにする
@MainActor
final class CreditStore: ObservableObject {
    @Published private(set) var credits: Int
    /// azuki-api側でユーザーを識別するためのID。初回作成後はKeychainで保持する。
    let userId: String

//    private let userDefaults: UserDefaults
    private let keychain: KeychainStorage
    private let storageKey = "azuki.credit.balance"
    private let keychainBalanceKey = "azuki.credit.balance"

    init(userDefaults: UserDefaults = .standard, keychain: KeychainStorage = KeychainStorage()) {
//        self.userDefaults = userDefaults
        self.keychain = keychain
        // 既存ユーザーであればKeychainから、旧バージョン利用者であればUserDefaultsからIDを復元する
        self.userId = AzukiUserIdentifier.loadOrCreate(keychain: keychain)

        if let storedInKeychain = keychain.loadInt(forKey: keychainBalanceKey) {
            // Keychainに保存済みならそのまま採用する
            self.credits = storedInKeychain
        } else {
//            // 旧バージョンのデータ移行：UserDefaultsに値があれば読み出してKeychainへ移す
//            let storedValue = userDefaults.integer(forKey: storageKey)
//            if userDefaults.object(forKey: storageKey) != nil {
//                self.credits = storedValue
//                keychain.saveInt(storedValue, forKey: keychainBalanceKey)
//            } else {
                self.credits = 0
//            }
        }
    }

    /// クレジットを追加する
    func add(credits amount: Int) {
        // 負値が来ても安全なように上限チェックを行う（0未満なら何もしない）
        if amount < 1 {
            return
        }
        // アプリ仕様：保有枚数が0枚の状態でのみ購入処理が通るため、ここでは単純に加算する
        // （サーバー同期で多めに返ってきた場合も想定し、正の数であればそのまま足し込む）
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
            // 負の値が来た場合は安全側として0枚に矯正する
            credits = 0
        } else {
            // 上限を撤廃したため、サーバー値をそのまま反映する
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
        // Keychainに書き込み
        keychain.saveInt(credits, forKey: keychainBalanceKey)
//        userDefaults.set(credits, forKey: storageKey)
    }
}

/// azuki-apiがユーザーを一意に判定するためのIDを管理するヘルパ
private enum AzukiUserIdentifier {
    private static let storageKey = "azuki.api.userId"

    /// Keychainに保存済みであればそれを返し、無ければ新たにUUIDを生成して保存する
    /// - Parameters:
    ///   - keychain: アプリ再インストール後も維持したい本来の保存先
    /// - Returns: APIへ渡すuserId文字列
    static func loadOrCreate(keychain: KeychainStorage) -> String {
        if let storedInKeychain = keychain.loadString(forKey: storageKey), storedInKeychain.isEmpty == false {
            return storedInKeychain
        }
//        if let storedInDefaults = userDefaults.string(forKey: storageKey), storedInDefaults.isEmpty == false {
//            keychain.saveString(storedInDefaults, forKey: storageKey)
//            return storedInDefaults
//        }
        let newId = UUID().uuidString.lowercased()
//        userDefaults.set(newId, forKey: storageKey)
        keychain.saveString(newId, forKey: storageKey)
        return newId
    }
}
