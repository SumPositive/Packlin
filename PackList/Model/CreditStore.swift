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
    /// azuki-api側でユーザーを識別するためのID。必要になるまでは生成を遅延させ、
    /// DEBUG起動でKeychainを空のまま確認できるようにする
    private(set) lazy var userId: String = {
        // 初回アクセス時にのみUUIDを採番し、Keychainへ書き戻す
        AzukiUserIdentifier.loadOrCreate(keychain: keychain)
    }()
    /// AdMobのSSV customDataへ付与する広告識別子。同様に必要になるまで生成を遅らせる
    private(set) lazy var userAdId: String = {
        // 広告動画を開くタイミングで初めて作成されるようにし、未購入状態でもKeychainが空のままになる
        AzukiAdUserIdentifier.loadOrCreate(keychain: keychain)
    }()

    private let keychain: KeychainStorage
    private let keychainBalanceKey = "azuki.credit.balance"

    init(keychain: KeychainStorage = KeychainStorage()) {
        self.keychain = keychain
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
    }
#if DEBUG
    /// DEBUGビルドでのアプリ起動前に、ユーザーIDと広告用IDを意図的にリセットするためのヘルパ
    /// - Parameter keychain: デバッグ時にクリア対象とするKeychainストレージ。指定が無ければ新規を生成する
    static func resetIdentifiersForDebugLaunch(keychain: KeychainStorage = KeychainStorage()) {
        // 旧インストールの残骸が残っていても、毎回クリーンな未購入状態で検証できるようにリセットする
        AzukiUserIdentifier.reset(keychain: keychain)
        AzukiAdUserIdentifier.reset(keychain: keychain)
    }
#endif
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

    /// DEBUGモードの初回起動でKeychain上のIDをクリアするためのヘルパ
    /// - Parameter keychain: 削除対象を保持しているKeychainストレージ
    static func reset(keychain: KeychainStorage) {
        // 削除のみを行い、次回以降のloadOrCreateで新規IDが採番されるようにする
        keychain.deleteItem(forKey: storageKey)
    }
}

/// AdMob SSV向けに利用する広告用の識別子を管理するヘルパ
private enum AzukiAdUserIdentifier {
    private static let storageKey = "azuki.api.userAdId"

    /// Keychainに保存済みであればそれを返し、無ければUUIDから生成する
    /// - Parameter keychain: セキュアに保持するためのKeychainストレージ
    /// - Returns: AdMobのcustomDataへ付与する文字列
    static func loadOrCreate(keychain: KeychainStorage) -> String {
        if let storedInKeychain = keychain.loadString(forKey: storageKey), storedInKeychain.isEmpty == false {
            return storedInKeychain
        }
        let newId = "ad-" + UUID().uuidString.lowercased()
        keychain.saveString(newId, forKey: storageKey)
        return newId
    }

    /// DEBUGモードの初回起動で広告用IDをリセットするヘルパ
    /// - Parameter keychain: 削除対象を保持しているKeychainストレージ
    static func reset(keychain: KeychainStorage) {
        // customDataに以前の値が残らないよう、Keychainから完全削除しておく
        keychain.deleteItem(forKey: storageKey)
    }
}
