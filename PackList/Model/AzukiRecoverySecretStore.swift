//
//  AzukiRecoverySecretStore.swift
//  PackList
//
//  Created by sumpo on 2026/11/01.
//

import Foundation
import Security

/// azuki-api の復旧用の秘密情報を管理するヘルパ
/// userId だけではトークンを発行させないための本人確認に使う
/// - iCloud キーチェーンで同じ Apple ID の端末へ同期し、新端末でもこの秘密情報でトークンを取り直せるようにする
/// - iCloud の Key-Value Store には置かない（機密情報を置かないよう Apple が案内しているため。userId はそちらのまま）
/// - userId ごとに別の項目にする（仮の userId から元の userId へ切り替わっても混ざらないように）
final class AzukiRecoverySecretStore {
    /// iCloud キーチェーンで同期する秘密情報の保存先
    private let syncedKeychain: KeychainStorage
    /// この端末がサーバーへ登録した秘密情報の控えと、登録の競合の印（この端末だけに保存する）
    /// 控えは、同期で別の値に入れ替わったときの更新（旧秘密情報の確認）と、同期の値が消えたときの書き戻しに使う
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
    /// 保存できなければ nil を返す（端末に残っていない値をサーバーへ登録すると、誰も復旧できないアカウントになるため）
    /// 登録が競合した後は作らない（別端末が登録済みの値が同期で届くのを待つ）
    func secretCreatingIfNeeded(for userId: String) -> String? {
        if let existing = secret(for: userId) {
            return existing
        }
        if hasConflict(for: userId) {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        let created = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard saveSynced(created, for: userId) else {
            log(.error, "recovery secret save failed")
            return nil
        }
        return created
    }

    /// この端末がサーバーへ登録した秘密情報（更新時に旧秘密情報として送る）
    func registeredSecret(for userId: String) -> String? {
        localKeychain.loadString(forKey: registeredKey(userId))
    }

    /// この秘密情報をサーバーへ登録済みか
    /// 端末間で同期した値が入れ替わったときは未登録とみなし、登録し直す
    func isRegistered(_ secret: String, for userId: String) -> Bool {
        registeredSecret(for: userId) == secret
    }

    /// サーバーへ登録できた（またはサーバーの値と一致した）ので控え、競合の印を外す
    func markRegistered(_ secret: String, for userId: String) {
        localKeychain.saveString(secret, forKey: registeredKey(userId))
        localKeychain.deleteItem(forKey: conflictKey(userId))
    }

    /// 別端末が先に別の値を登録していた
    func markConflict(for userId: String) {
        localKeychain.saveString("1", forKey: conflictKey(userId))
    }

    func hasConflict(for userId: String) -> Bool {
        localKeychain.loadString(forKey: conflictKey(userId)) == "1"
    }

    /// 同期の値が消えていたら、この端末が登録した控えを書き戻す
    /// （競合した端末が自分の値を捨てたとき、同期で登録済みの値まで消えることがあるため）
    func restoreSyncedIfMissing(for userId: String) {
        guard secret(for: userId) == nil, let registered = registeredSecret(for: userId) else { return }
        _ = saveSynced(registered, for: userId)
    }

    /// 同期の値がこの値のままなら捨てる（どこにも登録されていない値を、他端末へ広めないため）
    func discardSynced(ifEquals secret: String, for userId: String) {
        guard self.secret(for: userId) == secret else { return }
        syncedKeychain.deleteItem(forKey: secretKey(userId))
    }

    /// 保存の成否に加え、読み戻して同じ値が入っていることまで確かめる
    private func saveSynced(_ secret: String, for userId: String) -> Bool {
        syncedKeychain.saveString(secret, forKey: secretKey(userId)) && self.secret(for: userId) == secret
    }

    private func secretKey(_ userId: String) -> String {
        "com.azukid.azuki-api.recoverySecret.\(userId)"
    }

    private func registeredKey(_ userId: String) -> String {
        "com.azukid.azuki-api.recoverySecretRegistered.\(userId)"
    }

    private func conflictKey(_ userId: String) -> String {
        "com.azukid.azuki-api.recoverySecretConflict.\(userId)"
    }
}
