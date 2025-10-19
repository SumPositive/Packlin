//
//  AzukiAccessTokenStore.swift
//  PackList
//
//  Created by OpenAI on 2025/03/09.
//

import Foundation

/// azuki-apiが払い出すアクセストークンをKeychainへ保存・読込するためのヘルパ
/// - Note: 有効期限が過ぎたトークンは即座に破棄し、サーバーから再取得させる
final class AzukiAccessTokenStore {
    /// トークン本体をKeychainへ保存する際のキー
    private let tokenKey = "azuki.api.accessToken"
    /// 有効期限(ミリ秒)をKeychainへ保存する際のキー
    private let expiryKey = "azuki.api.accessTokenExpiry"
    /// 期限切れを判定する際の猶予秒数（ネットワーク遅延を考慮して少し短く扱う）
    private let leewaySeconds: TimeInterval = 30
    /// Keychainへアクセスするためのユーティリティ
    private let keychain: KeychainStorage

    init(keychain: KeychainStorage = KeychainStorage()) {
        self.keychain = keychain
    }

    /// Keychainから有効なアクセストークンを取得する
    /// - Returns: 期限内のトークンが存在すればその文字列、無ければnil
    func currentTokenIfValid() -> String? {
        guard let storedToken = keychain.loadString(forKey: tokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              storedToken.isEmpty == false else {
            return nil
        }
        guard let expiryMillisString = keychain.loadString(forKey: expiryKey),
              let expiryMillis = Double(expiryMillisString) else {
            clear()
            return nil
        }
        if expiryMillis < 1 {
            clear()
            return nil
        }
        let nowMillis = Date().timeIntervalSince1970 * 1000
        let leewayMillis = leewaySeconds * 1000
        if expiryMillis < nowMillis + leewayMillis {
            clear()
            return nil
        }
        return storedToken
    }

    /// トークンと有効期限をKeychainへ保存する
    /// - Parameters:
    ///   - token: サーバーが払い出したアクセストークン
    ///   - expiresAtMilliseconds: UNIXエポック基準の有効期限（ミリ秒）
    func save(token: String, expiresAtMilliseconds: Double) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear()
            return
        }
        if expiresAtMilliseconds < 1 {
            clear()
            return
        }
        keychain.saveString(trimmed, forKey: tokenKey)
        keychain.saveString(String(expiresAtMilliseconds), forKey: expiryKey)
    }

    /// Keychainからアクセストークン情報を削除する
    func clear() {
        keychain.deleteItem(forKey: tokenKey)
        keychain.deleteItem(forKey: expiryKey)
    }
}
