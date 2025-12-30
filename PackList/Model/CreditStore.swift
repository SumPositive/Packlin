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
    /// azuki-api側でユーザーを識別するためのID。StoreKit購入時にも利用するため
    /// アプリ起動と同時にKeychainへ用意しておく。デバッグ時の即時更新に備えてPublishedで公開する
    @Published private(set) var userId: String

    private let keychain: KeychainStorage
    private let keychainBalanceKey = "azuki.credit.balance"

    init(keychain: KeychainStorage = KeychainStorage()) {
        self.keychain = keychain
        // ユーザーIDは起動時に確定させる。広告用IDを別途管理する必要がなくなったため、userIdのみで統一
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

    /// AdMobのSSVでuserIdが欠けた場合にも、即座に再発行してKeychainへ保存する
    /// - Returns: 確実にKeychainへ保存された最新のuserId
    @discardableResult
    func regenerateUserIdIfNeeded() -> String {
        // Keychain削除後などで空文字になった場合に備え、ここで新規発行する
        if userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let regeneratedId = AzukiUserIdentifier.loadOrCreate(keychain: keychain)
            // 発行直後にPublished経由でUIへ流すため、メモリ上も更新しておく
            userId = regeneratedId
        }
        return userId
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

    #if DEBUG
    /// Keychainに保存されたユーザーIDとクレジット残高を削除して初期状態に戻す（デバッグ専用）
    func deleteUserIdForDebug() {
        // ここでは再発行せずに純粋な初期状態へ戻す
        AzukiUserIdentifier.delete(keychain: keychain)
        // クレジットも同時にクリアし、Keychainから削除してからメモリ上の値を0にそろえる
        keychain.deleteItem(forKey: keychainBalanceKey)
        credits = 0
        // Publishedを通じてUIへ即座に反映させるため空文字を反映
        userId = ""
    }
    #endif

    private func persist() {
        // Keychainに書き込み
        keychain.saveInt(credits, forKey: keychainBalanceKey)
    }
}

/// azuki-apiがユーザーを一意に判定するためのIDを管理するヘルパ
private enum AzukiUserIdentifier {
    fileprivate static let storageKey = "azuki.api.userId"

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

    #if DEBUG
    /// Keychainに保存されたユーザーIDを削除する（デバッグ専用）
    /// - Parameter keychain: 削除先となるKeychain
    static func delete(keychain: KeychainStorage) {
        // SecItemDeleteに任せ、存在しない場合でもエラーとしない
        keychain.deleteItem(forKey: storageKey)
    }
    #endif

}
