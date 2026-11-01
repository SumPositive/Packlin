//
//  AzukiRecoverySecretStore.swift
//  PackList
//
//  Created by sumpo on 2026/11/01.
//

import Foundation
import CryptoKit
import Security

/// azuki-api の復旧用の秘密情報を管理するヘルパ
/// userId だけではトークンを発行させないための本人確認に使う
/// - iCloud キーチェーンで同じ Apple ID の端末へ同期し、新端末でもこの秘密情報でトークンを取り直せるようにする
/// - iCloud の Key-Value Store には置かない（機密情報を置かないよう Apple が案内しているため。userId はそちらのまま）
/// - userId ごとに別の項目にする（仮の userId から元の userId へ切り替わっても混ざらないように）
final class AzukiRecoverySecretStore {
    /// iCloud キーチェーンで同期する秘密情報の保存先
    private let syncedKeychain: KeychainStorage
    /// サーバーへ登録済みの秘密情報の指紋（この端末だけに保存する）
    private let localKeychain: KeychainStorage

    init(syncedKeychain: KeychainStorage = KeychainStorage(synchronizable: true),
         localKeychain: KeychainStorage = KeychainStorage()) {
        self.syncedKeychain = syncedKeychain
        self.localKeychain = localKeychain
    }

    /// 同期済みの秘密情報（新端末ではまだ届いていないことがある）
    func secret(for userId: String) -> String? {
        guard let value = syncedKeychain.loadString(forKey: secretKey(userId)), value.isEmpty == false else {
            return nil
        }
        return value
    }

    /// 秘密情報を返す。無ければ 32 バイトの乱数で作って保存する
    /// サーバーへ登録できるのは本人のトークンを持っているときだけなので、作るのもそのときに限る
    func secretCreatingIfNeeded(for userId: String) -> String? {
        if let existing = secret(for: userId) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        let created = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        syncedKeychain.saveString(created, forKey: secretKey(userId))
        return created
    }

    /// この秘密情報をサーバーへ登録済みか
    /// 端末間で同期した値が入れ替わったときは未登録とみなし、登録し直す
    func isRegistered(_ secret: String, for userId: String) -> Bool {
        localKeychain.loadString(forKey: registeredKey(userId)) == fingerprint(secret)
    }

    func markRegistered(_ secret: String, for userId: String) {
        localKeychain.saveString(fingerprint(secret), forKey: registeredKey(userId))
    }

    private func secretKey(_ userId: String) -> String {
        "com.azukid.azuki-api.recoverySecret.\(userId)"
    }

    private func registeredKey(_ userId: String) -> String {
        "com.azukid.azuki-api.recoverySecretRegistered.\(userId)"
    }

    private func fingerprint(_ secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
