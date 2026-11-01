//
//  AzukiRefreshTokenStore.swift
//  PackList
//
//  Created by OpenAI on 2025/10/25.
//

import Foundation

/// azuki-api が払い出すリフレッシュトークンを Keychain へ保存・復元するヘルパ
/// - Note: 有効期限切れ直前での連続リフレッシュを避けるため、少し余裕を持って破棄する
final class AzukiRefreshTokenStore {
    /// Keychain へ保存する際のトークン本体キー
    private let tokenKey = "com.azukid.azuki-api.refreshToken"
    /// リフレッシュトークンの有効期限(ミリ秒)を保存する際のキー
    private let expiryKey = "com.azukid.azuki-api.refreshTokenExpiry"
    /// リフレッシュトークンの発行先の端末ID（更新時に同じIDを送る）
    private let deviceIdKey = "com.azukid.azuki-api.refreshTokenDeviceId"
    /// 有効期限チェック時に設ける猶予秒数
    private let leewaySeconds: TimeInterval = 60
    /// Keychain へ実際にアクセスするためのユーティリティ
    private let keychain: KeychainStorage

    init(keychain: KeychainStorage = KeychainStorage()) {
        self.keychain = keychain
    }

    /// 保存済みのリフレッシュトークンが期限内かを確認して返す
    /// - Returns: 期限を満たしていればトークン文字列、無ければ nil
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
        if expiryMillis <= nowMillis + leewayMillis {
            clear()
            return nil
        }
        return storedToken
    }

    /// リフレッシュトークンと期限を Keychain へ保存する
    /// - Parameters:
    ///   - token: サーバーが払い出したリフレッシュトークン
    ///   - expiresAtMilliseconds: UNIX エポック基準の有効期限（ミリ秒）
    ///   - deviceId: サーバーがこのトークンを発行した端末ID（分からなければ nil）
    func save(token: String, expiresAtMilliseconds: Double, deviceId: String?) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear()
            return
        }
        if expiresAtMilliseconds < 1 {
            clear()
            return
        }
        let normalizedExpiry = String(expiresAtMilliseconds)
        keychain.saveString(trimmed, forKey: tokenKey)
        keychain.saveString(normalizedExpiry, forKey: expiryKey)
        if let deviceId, deviceId.isEmpty == false {
            keychain.saveString(deviceId, forKey: deviceIdKey)
        } else {
            // 前のトークンの発行先を使い回さない
            keychain.deleteItem(forKey: deviceIdKey)
        }
    }

    /// 保存中のリフレッシュトークンの発行先の端末ID
    func currentDeviceId() -> String? {
        keychain.loadString(forKey: deviceIdKey)
    }

    /// Keychain からリフレッシュトークン情報を削除する
    func clear() {
        keychain.deleteItem(forKey: tokenKey)
        keychain.deleteItem(forKey: expiryKey)
        keychain.deleteItem(forKey: deviceIdKey)
    }
}
