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
        // デバッグでuserIdを空にすると旧ユーザー向けのアクセストークンが残ってしまうため、
        // サーバーの認証エラーを避ける目的でアクセストークンとリフレッシュトークンも破棄する
        AzukiApi.shared.clearAuthenticationStateForUserReset()
        // Keychain にキャッシュされた App Attest 証明書も破棄し、次回購入時に再 Attest させる
        AzukiApi.shared.invalidateDeviceIdentityForDebug()
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

    /// userId を解決する。優先順位は以下（端末故障後も同じ Apple ID で復元できるようにする）:
    ///   1. Keychain にあればそれを採用（現役の残高・トークンとの整合を最優先）。
    ///      このとき iCloud 側が未設定なら iCloud にも写して、既存ユーザーも次回以降復元可能にする。
    ///   2. Keychain に無く iCloud にあれば、それを採用して Keychain へ書き戻す（機種変更後の復元）。
    ///   3. どちらにも無ければ新規 UUID を生成し、Keychain と iCloud の両方へ保存する。
    /// - Parameters:
    ///   - keychain: アプリ再インストール後も維持したい本来の保存先
    ///   - iCloud: 端末をまたいで userId を引き継ぐための iCloud Key-Value Store
    /// - Returns: APIへ渡すuserId文字列
    static func loadOrCreate(keychain: KeychainStorage,
                             iCloud: ICloudKeyValueStore = ICloudKeyValueStore()) -> String {
        // 1. Keychain 優先
        if let storedInKeychain = keychain.loadString(forKey: storageKey), storedInKeychain.isEmpty == false {
            // 既存ユーザーの移行: iCloud 未設定なら写しておく（次回以降の復元に備える）
            if iCloud.loadString(forKey: storageKey) == nil {
                iCloud.saveString(storedInKeychain, forKey: storageKey)
            }
            return storedInKeychain
        }
        // 2. iCloud からの復元（機種変更・端末故障後の新端末など）
        if let storedInICloud = iCloud.loadString(forKey: storageKey), storedInICloud.isEmpty == false {
            keychain.saveString(storedInICloud, forKey: storageKey)
            return storedInICloud
        }
        // 3. 新規発行 → Keychain と iCloud の両方へ保存
        let newId = UUID().uuidString.lowercased()
        keychain.saveString(newId, forKey: storageKey)
        iCloud.saveString(newId, forKey: storageKey)
        return newId
    }

    #if DEBUG
    /// 保存されたユーザーIDを削除する（デバッグ専用）。
    /// Keychain だけ消しても iCloud から復元されてしまうため、iCloud 側も削除する。
    /// - Parameters:
    ///   - keychain: 削除先となるKeychain
    ///   - iCloud: 削除先となる iCloud Key-Value Store
    static func delete(keychain: KeychainStorage,
                       iCloud: ICloudKeyValueStore = ICloudKeyValueStore()) {
        // SecItemDeleteに任せ、存在しない場合でもエラーとしない
        keychain.deleteItem(forKey: storageKey)
        iCloud.removeValue(forKey: storageKey)
    }
    #endif

}
