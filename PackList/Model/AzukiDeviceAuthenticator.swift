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
    /// /api/device/register 完了フラグを保存する Keychain キー
    private let registeredKey = "com.azukid.azuki-api.device.registered"
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
        // すでにメモリ／Keychain に情報があれば、それをそのまま返す
        if let existing = currentIdentity() {
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
        // アテステーションオブジェクトから公開鍵（COSE 形式）を解析して取り出す
        let publicKeyData = try exportPublicKey(fromAttestation: attestationData)
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
        keychain.deleteItem(forKey: registeredKey)
    }

    /// /api/device/register への送信が完了したことを Keychain へ記録する
    func confirmDeviceRegistration() {
        keychain.saveString("1", forKey: registeredKey)
    }

    /// サーバーへの端末登録が完了しているかを返す
    func isDeviceRegistered() -> Bool {
        return keychain.loadString(forKey: registeredKey) == "1"
    }

    /// 購入検証用のアサーションを生成する
    /// - Parameter transactionId: StoreKit のトランザクション ID。署名のクライアントデータとして使用する。
    /// - Returns: サーバーへ送信するデバイス ID とアサーション（Base64）
    func generatePurchaseAssertion(transactionId: String) async throws -> (deviceId: String, assertion: String) {
        guard let identity = cachedIdentity ?? loadIdentityFromKeychain() else {
            throw AuthenticatorError.identityUnavailable
        }
        // clientDataHash = SHA-256(transactionId.utf8)  ←サーバー側と同じ計算
        let clientDataHash = Data(SHA256.hash(data: Data(transactionId.utf8)))
        let assertionData = try await generateAssertion(keyId: identity.attestKeyId, messageHash: clientDataHash)
        return (deviceId: identity.deviceId, assertion: assertionData.base64EncodedString())
    }

    /// 復旧リクエスト用のアサーションを生成する
    /// - Parameter userId: ユーザー ID。署名のクライアントデータとして使用する。
    /// - Returns: サーバーへ送信するデバイス ID とアサーション（Base64）
    func generateRecoverAssertion(userId: String) async throws -> (deviceId: String, assertion: String) {
        guard let identity = cachedIdentity ?? loadIdentityFromKeychain() else {
            throw AuthenticatorError.identityUnavailable
        }
        let clientDataHash = Data(SHA256.hash(data: Data(userId.utf8)))
        let assertionData = try await generateAssertion(keyId: identity.attestKeyId, messageHash: clientDataHash)
        return (deviceId: identity.deviceId, assertion: assertionData.base64EncodedString())
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

    /// アテステーションオブジェクトから公開鍵（未圧縮 ANSI X9.63 形式）を抽出する
    /// - Note: `DCAppAttestService` から直接鍵を取り出す API が古い SDK では存在しないため、
    ///         アテステーション (`attestationObject`) に含まれる COSE 公開鍵を自力で解析する
    private func exportPublicKey(fromAttestation attestationObject: Data) throws -> Data {
        do {
            // まず CBOR のマップから `authData` フィールドを抜き出す
            let authData = try extractAuthData(fromAttestationObject: attestationObject)
            // `authData` の後半に付随する COSE 公開鍵を復元して未圧縮形式へ変換する
            let publicKey = try extractPublicKey(fromAuthData: authData)
            return publicKey
        } catch {
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }
    }

    /// アテステーションオブジェクトの CBOR マップから `authData` を取り出す
    private func extractAuthData(fromAttestationObject attestationObject: Data) throws -> Data {
        var reader = CBORReader(data: attestationObject)
        let pairCount = try reader.readMapHeader()
        var authDataCandidate: Data?
        for _ in 0..<pairCount {
            let key = try reader.readTextString()
            if key == "authData" {
                authDataCandidate = try reader.readByteString()
            } else {
                try reader.skipItem()
            }
        }
        if let authData = authDataCandidate {
            return authData
        }
        throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
    }

    /// `authData` から COSE 公開鍵を解析して未圧縮形式へ変換する
    private func extractPublicKey(fromAuthData authData: Data) throws -> Data {
        // App Attest の `authData` 形式は WebAuthn の Attested Credential Data と同等
        // 32 バイトの RP ID ハッシュ + 1 バイトのフラグ + 4 バイトの署名カウンタが先頭
        var cursor = 0
        let minimumHeaderSize = 32 + 1 + 4
        if authData.count < minimumHeaderSize {
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }
        cursor += 32 // RP ID ハッシュを読み飛ばす
        let flags = authData[cursor]
        cursor += 1
        cursor += 4 // 署名カウンタを読み飛ばす
        // フラグの 0x40 (AT) が立っていないと公開鍵が含まれない
        if flags & 0x40 == 0 {
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }
        let remaining = authData.suffix(from: cursor)
        // AAGUID (16 バイト) + Credential ID 長 (2 バイト) + Credential ID 本体...
        if remaining.count < 18 {
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }
        var index = remaining.startIndex
        index = remaining.index(index, offsetBy: 16)
        let lengthHigh = Int(remaining[index])
        index = remaining.index(after: index)
        let lengthLow = Int(remaining[index])
        index = remaining.index(after: index)
        let credentialIdLength = (lengthHigh << 8) + lengthLow
        if remaining.distance(from: index, to: remaining.endIndex) < credentialIdLength {
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }
        index = remaining.index(index, offsetBy: credentialIdLength)
        let publicKeySlice = remaining[index..<remaining.endIndex]
        var publicKeyReader = CBORReader(data: Data(publicKeySlice))
        let coseMap = try publicKeyReader.readCOSEKeyMap()
        guard let xCoord = coseMap[-2], let yCoord = coseMap[-3] else {
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }
        // 未圧縮形式は 0x04 + X 座標 (32 バイト) + Y 座標 (32 バイト)
        if xCoord.count != 32 || yCoord.count != 32 {
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }
        var uncompressed = Data([0x04])
        uncompressed.append(xCoord)
        uncompressed.append(yCoord)
        return uncompressed
    }

    /// 最低限必要な CBOR 解析を担う小さなリーダー構造体
    private struct CBORReader {
        /// 元となる CBOR バイト列
        private let data: Data
        /// 現在の読み取り位置（インデックス）
        private var cursor: Data.Index

        init(data: Data) {
            self.data = data
            self.cursor = data.startIndex
        }

        /// マップのヘッダを読み込み、エントリ数を返す
        mutating func readMapHeader() throws -> Int {
            let (major, info) = try readTypeAndInfo()
            if major != 5 {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            if info == 31 {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            let length = try readLength(additionalInfo: info)
            if UInt64(Int.max) < length {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            return Int(length)
        }

        /// テキスト文字列としてデコードする
        mutating func readTextString() throws -> String {
            let (major, info) = try readTypeAndInfo()
            if major != 3 {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            let length = try readLength(additionalInfo: info)
            if UInt64(Int.max) < length {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            let bytes = try readBytes(count: Int(length))
            guard let string = String(data: bytes, encoding: .utf8) else {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            return string
        }

        /// バイト列をそのまま返す
        mutating func readByteString() throws -> Data {
            let (major, info) = try readTypeAndInfo()
            if major != 2 {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            let length = try readLength(additionalInfo: info)
            if UInt64(Int.max) < length {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            return try readBytes(count: Int(length))
        }

        /// 任意項目を読み飛ばす（ネスト対応）
        mutating func skipItem() throws {
            let (major, info) = try readTypeAndInfo()
            try skipItem(major: major, info: info)
        }

        /// COSE 鍵を表すマップを読み取り、整数キーとデータの辞書に整形する
        mutating func readCOSEKeyMap() throws -> [Int: Data] {
            let (major, info) = try readTypeAndInfo()
            if major != 5 {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            if info == 31 {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            let pairCount = try readLength(additionalInfo: info)
            if UInt64(Int.max) < pairCount {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            var result: [Int: Data] = [:]
            for _ in 0..<Int(pairCount) {
                let key = try readInteger()
                if let value = try readOptionalByteString() {
                    result[key] = value
                }
            }
            return result
        }

        /// 整数（正負両方）を読み取る
        private mutating func readInteger() throws -> Int {
            let (major, info) = try readTypeAndInfo()
            switch major {
            case 0:
                let value = try readLength(additionalInfo: info)
                if UInt64(Int.max) < value {
                    throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
                }
                return Int(value)
            case 1:
                let magnitude = try readLength(additionalInfo: info)
                if UInt64(Int64.max) < magnitude {
                    throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
                }
                let signed = -1 - Int64(magnitude)
                return Int(signed)
            default:
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
        }

        /// バイト列なら取り出し、それ以外は読み飛ばす
        private mutating func readOptionalByteString() throws -> Data? {
            let (major, info) = try readTypeAndInfo()
            if major == 2 {
                let length = try readLength(additionalInfo: info)
                if UInt64(Int.max) < length {
                    throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
                }
                return try readBytes(count: Int(length))
            }
            try skipItem(major: major, info: info)
            return nil
        }

        /// 型と追加情報を 1 バイト読み取る
        private mutating func readTypeAndInfo() throws -> (UInt8, UInt8) {
            guard cursor < data.endIndex else {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            let byte = data[cursor]
            cursor = data.index(after: cursor)
            let major = byte >> 5
            let info = byte & 0x1F
            return (major, info)
        }

        /// 追加情報から長さを解釈する
        private mutating func readLength(additionalInfo info: UInt8) throws -> UInt64 {
            if info <= 23 {
                return UInt64(info)
            }
            if info == 24 {
                let bytes = try readBytes(count: 1)
                return UInt64(bytes[bytes.startIndex])
            }
            if info == 25 {
                let bytes = try readBytes(count: 2)
                return bytes.reduce(0) { ($0 << 8) + UInt64($1) }
            }
            if info == 26 {
                let bytes = try readBytes(count: 4)
                return bytes.reduce(0) { ($0 << 8) + UInt64($1) }
            }
            if info == 27 {
                let bytes = try readBytes(count: 8)
                return bytes.reduce(0) { ($0 << 8) + UInt64($1) }
            }
            throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
        }

        /// 指定バイト数を切り出す
        private mutating func readBytes(count: Int) throws -> Data {
            let available = data.distance(from: cursor, to: data.endIndex)
            if available < count {
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
            let end = data.index(cursor, offsetBy: count)
            let slice = data[cursor..<end]
            cursor = end
            return Data(slice)
        }

        /// 既知の型に応じて読み飛ばし処理を行う
        private mutating func skipItem(major: UInt8, info: UInt8) throws {
            switch major {
            case 0, 1:
                _ = try readLength(additionalInfo: info)
            case 2, 3:
                let length = try readLength(additionalInfo: info)
                if UInt64(Int.max) < length {
                    throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
                }
                _ = try readBytes(count: Int(length))
            case 4:
                let count = try readLength(additionalInfo: info)
                if UInt64(Int.max) < count {
                    throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
                }
                for _ in 0..<Int(count) {
                    try skipItem()
                }
            case 5:
                let count = try readLength(additionalInfo: info)
                if UInt64(Int.max) < count {
                    throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
                }
                for _ in 0..<Int(count) {
                    try skipItem()
                    try skipItem()
                }
            case 6:
                _ = try readLength(additionalInfo: info)
                try skipItem()
            case 7:
                if info <= 23 {
                    return
                }
                if info == 24 {
                    _ = try readBytes(count: 1)
                    return
                }
                if info == 25 {
                    _ = try readBytes(count: 2)
                    return
                }
                if info == 26 {
                    _ = try readBytes(count: 4)
                    return
                }
                if info == 27 {
                    _ = try readBytes(count: 8)
                    return
                }
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            default:
                throw AzukiDeviceAuthenticator.AuthenticatorError.publicKeyExportFailed
            }
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
