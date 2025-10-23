//
//  AzukiDeviceAuthenticator.swift
//  PackList
//
//  Created by OpenAI on 2025/10/30.
//

import Foundation
import CryptoKit
import DeviceCheck
import Security

/// App Attest を利用して端末固有の鍵ペアとアテステーション情報を管理するアクタ
/// - Note: サーバーが要求する "deviceId" やアテステーション情報をまとめて払い出す
actor AzukiDeviceAuthenticator {
    /// サーバーへ送信する端末識別情報のまとまり
    struct DeviceIdentity {
        /// サーバー側で `app_devices.device_id` として保持される識別子
        let deviceId: String
        /// App Attest の鍵 ID。サーバーで署名検証を行う際に利用する
        let attestKeyId: String
        /// 端末側の公開鍵（圧縮形式）。サーバーはこれを保存して Bearer チャレンジ検証に活用する
        let devicePublicKey: String
        /// App Attest `attestKey` から得られるアテステーション（DERをBase64化）
        let attestation: String
        /// アテステーションを生成する際に利用したチャレンジ文字列（Base64エンコード済み）
        let attestationChallenge: String
    }

    /// リフレッシュチャレンジへ応答するために必要な署名情報
    struct RefreshSignaturePayload {
        /// サーバーへ返却する署名文字列（Base64エンコード済み）
        let signature: String
        /// 署名生成時刻（ISO8601文字列）
        let signedAt: String
        /// 署名に含めた `refreshToken` の SHA-256 ハッシュ（Base64エンコード）
        let refreshTokenHash: String
    }

    /// 端末側で発生し得るエラー
    enum AuthenticatorError: Error {
        case unsupported
        case keyGenerationFailed
        case attestationFailed
        case publicKeyExportFailed
        case signatureFailed
        case identityUnavailable
    }

    /// Keychain へ JSON で保存する内部表現
    private struct StoredIdentity: Codable {
        let deviceId: String
        let attestKeyId: String
        let devicePublicKey: String
        let attestation: String
        let attestationChallenge: String
    }

    /// JSON エンコード・デコードを再利用するための共通インスタンス
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    /// App Attest サービスの共有インスタンス
    private let appAttestService = DCAppAttestService.shared
    /// Keychain アクセスを一元化するヘルパ
    private let keychain: KeychainStorage
    /// アテステーション情報を保存する Keychain キー
    private let identityStorageKey = "com.azukid.azuki-api.device.identity"
    /// アテステーション日時を保存する Keychain キー（再アテストの判断材料として保持）
    private let attestedAtKey = "com.azukid.azuki-api.device.attestedAt"
    /// ISO8601 フォーマッタを毎回生成するとコストが高いため、インスタンスを使い回す
    private let isoFormatter: ISO8601DateFormatter

    /// メモリ上に展開済みの端末識別情報
    private var cachedIdentity: StoredIdentity?

    init(keychain: KeychainStorage = KeychainStorage()) {
        self.keychain = keychain
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    /// すでにアテステーション済みの端末識別情報があれば返し、無ければ Secure Enclave で新規生成する
    /// - Returns: サーバーへ送信するための端末識別情報
    func ensureIdentity() async throws -> DeviceIdentity {
        if let existing = await currentIdentity() {
            return existing
        }
        if appAttestService.isSupported == false {
            throw AuthenticatorError.unsupported
        }
        // ランダムチャレンジは 32 バイト固定とし、サーバーへも同じ値を通知して照合してもらう
        let challengeData = try generateRandomChallenge()
        let challengeBase64 = challengeData.base64EncodedString()
        let keyId = try await generateKeyId()
        let attestationData = try await attestKey(keyId: keyId, challenge: challengeData)
        let attestationBase64 = attestationData.base64EncodedString()
        let publicKeyData = try exportPublicKey(keyId: keyId)
        let publicKeyBase64 = publicKeyData.base64EncodedString()
        // サーバー側では keyId をそのまま deviceId として扱う仕様のため、変換せず格納する
        let stored = StoredIdentity(
            deviceId: keyId,
            attestKeyId: keyId,
            devicePublicKey: publicKeyBase64,
            attestation: attestationBase64,
            attestationChallenge: challengeBase64
        )
        try persist(identity: stored)
        cachedIdentity = stored
        return DeviceIdentity(
            deviceId: stored.deviceId,
            attestKeyId: stored.attestKeyId,
            devicePublicKey: stored.devicePublicKey,
            attestation: stored.attestation,
            attestationChallenge: stored.attestationChallenge
        )
    }

    /// Keychain に保存済みの端末識別情報を読み出す
    /// - Returns: アテステーション済みなら情報、無ければ nil
    func currentIdentity() -> DeviceIdentity? {
        if let cached = cachedIdentity {
            return DeviceIdentity(
                deviceId: cached.deviceId,
                attestKeyId: cached.attestKeyId,
                devicePublicKey: cached.devicePublicKey,
                attestation: cached.attestation,
                attestationChallenge: cached.attestationChallenge
            )
        }
        guard let stored = loadIdentityFromKeychain() else {
            return nil
        }
        cachedIdentity = stored
        return DeviceIdentity(
            deviceId: stored.deviceId,
            attestKeyId: stored.attestKeyId,
            devicePublicKey: stored.devicePublicKey,
            attestation: stored.attestation,
            attestationChallenge: stored.attestationChallenge
        )
    }

    /// サーバー側で端末鍵が失効した際に呼び出し、Keychain 上のキャッシュを破棄する
    func invalidateIdentity() {
        cachedIdentity = nil
        keychain.deleteItem(forKey: identityStorageKey)
        keychain.deleteItem(forKey: attestedAtKey)
    }

    /// リフレッシュチャレンジへ応答する署名を生成する
    /// - Parameters:
    ///   - nonce: サーバーが払い出したチャレンジのノンス
    ///   - refreshToken: 署名に組み込む対象のリフレッシュトークン
    /// - Returns: サーバーへ送信すべき署名関連データ
    func signRefreshChallenge(nonce: String, refreshToken: String) async throws -> RefreshSignaturePayload {
        guard let identity = cachedIdentity ?? loadIdentityFromKeychain() else {
            throw AuthenticatorError.identityUnavailable
        }
        if appAttestService.isSupported == false {
            throw AuthenticatorError.unsupported
        }
        let signedAt = isoFormatter.string(from: Date())
        let refreshHash = sha256Base64(for: refreshToken)
        guard let nonceData = nonce.data(using: .utf8),
              let refreshHashData = Data(base64Encoded: refreshHash),
              let signedAtData = signedAt.data(using: .utf8) else {
            throw AuthenticatorError.signatureFailed
        }
        var message = Data()
        message.append(nonceData)
        message.append(refreshHashData)
        message.append(signedAtData)
        let messageHash = Data(SHA256.hash(data: message))
        let signatureData = try await generateAssertion(keyId: identity.attestKeyId, messageHash: messageHash)
        let signatureBase64 = signatureData.base64EncodedString()
        return RefreshSignaturePayload(
            signature: signatureBase64,
            signedAt: signedAt,
            refreshTokenHash: refreshHash
        )
    }

    /// Keychain へ端末識別情報を保存する
    private func persist(identity: StoredIdentity) throws {
        let data = try jsonEncoder.encode(identity)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw AuthenticatorError.attestationFailed
        }
        keychain.saveString(jsonString, forKey: identityStorageKey)
        let attestedAt = Date().timeIntervalSince1970
        keychain.saveString(String(attestedAt), forKey: attestedAtKey)
    }

    /// Keychain から JSON として保存された端末識別情報を復元する
    private func loadIdentityFromKeychain() -> StoredIdentity? {
        guard let jsonString = keychain.loadString(forKey: identityStorageKey),
              let data = jsonString.data(using: .utf8),
              let decoded = try? jsonDecoder.decode(StoredIdentity.self, from: data) else {
            return nil
        }
        return decoded
    }

    /// App Attest 用の鍵 ID を生成する
    private func generateKeyId() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.generateKey { keyId, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let keyId = keyId else {
                    continuation.resume(throwing: AuthenticatorError.keyGenerationFailed)
                    return
                }
                continuation.resume(returning: keyId)
            }
        }
    }

    /// App Attest で鍵のアテステーションを生成する
    private func attestKey(keyId: String, challenge: Data) async throws -> Data {
        let challengeHash = Data(SHA256.hash(data: challenge))
        return try await withCheckedThrowingContinuation { continuation in
            appAttestService.attestKey(keyId, clientDataHash: challengeHash) { attestation, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let attestation = attestation else {
                    continuation.resume(throwing: AuthenticatorError.attestationFailed)
                    return
                }
                continuation.resume(returning: attestation)
            }
        }
    }

    /// App Attest の秘密鍵から公開鍵を取り出す
    private func exportPublicKey(keyId: String) throws -> Data {
        do {
            let secKey = try appAttestService.key(forKey: keyId)
            guard let representation = SecKeyCopyExternalRepresentation(secKey, nil) as Data? else {
                throw AuthenticatorError.publicKeyExportFailed
            }
            return representation
        } catch {
            throw AuthenticatorError.publicKeyExportFailed
        }
    }

    /// App Attest の `generateAssertion` を async/await で扱いやすく包む
    private func generateAssertion(keyId: String, messageHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            appAttestService.generateAssertion(keyId, clientDataHash: messageHash) { assertion, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let assertion = assertion else {
                    continuation.resume(throwing: AuthenticatorError.signatureFailed)
                    return
                }
                continuation.resume(returning: assertion)
            }
        }
    }

    /// 32バイトの安全な乱数チャレンジを生成する
    private func generateRandomChallenge() throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        if status != errSecSuccess {
            throw AuthenticatorError.attestationFailed
        }
        return Data(buffer)
    }

    /// リフレッシュトークンのハッシュを Base64 文字列として算出する
    private func sha256Base64(for token: String) -> String {
        let tokenData = Data(token.utf8)
        let digest = SHA256.hash(data: tokenData)
        return Data(digest).base64EncodedString()
    }
}
