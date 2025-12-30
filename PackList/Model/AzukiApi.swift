//
//  AzukiApi.swift
//  PackList
//
//  Created by sumpo on 2025/10/12.
//

import Foundation
import FirebaseAnalytics

/// azuki-api へ問い合わせる際に発生するエラーをまとめる列挙
/// 日本語のLocalizedDescriptionを返してUIでそのまま表示できるようにする
enum AzukiAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int)
    case serverError(message: String)
    case decoding
    case encoding
    case insufficientCredits
    case missingAuthToken
    case unauthorized
    case forbiddenUser
    case duplicateTransaction
    case unknownProduct
    case purchaseMismatch
    case tokenExpired
    case receiptBelongsToOtherUser
    case deviceSecurityUnavailable
    case deviceSignatureFailed
    case notFound

    var errorDescription: String? {
        switch self {
            case .invalidURL: // サーバーのURLを組み立てられませんでした
                return errorMsg("invalidURL")
            case .invalidResponse: // サーバーの応答が不正でした
                return errorMsg("invalidResponse")
            case .server(let statusCode): // サーバーエラー
                return errorMsg("statusCode-\(statusCode)")
            case .serverError(let message): // サーバーエラー
                return errorMsg("serverError") //-\(message)")
            case .decoding: // サーバーから受信したデータを解析できません
                return errorMsg("decoding")
            case .encoding: // 送信データの準備に失敗しました
                return errorMsg("400-encoding")
            case .insufficientCredits: // クレジットが不足しています
                return errorMsg("402-insufficientCredits")
            case .missingAuthToken: // アクセストークンが見つかりません
                return errorMsg("401-missingAuthToken")
            case .unauthorized: // 認証に失敗しました
                return errorMsg("401-unauthorized")
            case .forbiddenUser: // ユーザー情報の検証に失敗しました
                return errorMsg("401-forbiddenUser")
            case .duplicateTransaction: // この購入はすでに処理済みです
                return errorMsg("409-duplicateTransaction")
            case .unknownProduct: // サーバー側の商品の登録と一致しません
                return errorMsg("406-unknownProduct")
            case .purchaseMismatch: // 購入情報の整合性を確認できません
                return errorMsg("400-purchaseMismatch")
            case .tokenExpired: // アクセストークンの有効期限が切れました
                return errorMsg("401-tokenExpired")
            case .receiptBelongsToOtherUser: // この購入情報は別のユーザーに紐づいています
                return errorMsg("400-receiptBelongsToOtherUser")
            case .deviceSecurityUnavailable: // 端末のセキュリティ機能を利用できません
                return errorMsg("400-deviceSecurityUnavailable")
            case .deviceSignatureFailed: // 端末認証に失敗しました
                return errorMsg("401-deviceSignatureFailed")
            case .notFound: // 404 サイトが見つかりません
                return errorMsg("404-notFound")
        }
        
        /// アプリユーザに見せるメッセージ
        func errorMsg(_ message: String) -> String {
            let msg = String(message.prefix(100))
            log(.error, msg) // Analytics.logEvent出力される
            return String(localized: "通信障害が発生しているようです。しばらくしてから再度お試しください")
                    + "\n\n [\(msg)]"
        }

    }
}

/// azuki-api との通信を担うクライアント
/// - Note: iOS側では決済処理そのものはStoreKit任せとし、azuki-apiはレシート検証とOpenAI代理実行を提供する想定
final class AzukiApi {
    static let shared = AzukiApi()

    /// /api/credit/check が返すクレジット状況
    struct CreditStatus {
        let balance: Int
        let adRewardBalance: Int
    }

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// サーバー発行のアクセストークンをKeychain経由で管理するストア
    private let accessTokenStore: AzukiAccessTokenStore
    /// サーバー発行のリフレッシュトークンをKeychain経由で管理するストア
    private let refreshTokenStore: AzukiRefreshTokenStore
    /// ビュー層などから注入されるトークン復旧ハンドラをスレッドセーフに保持するためのボックス
    private let tokenRecoveryHandlerBox = TokenRecoveryHandlerBox()
    /// リフレッシュ API への同時アクセスを直列化する調整役
    private let refreshCoordinator = RefreshCoordinator()
    /// App Attest を介した端末識別情報を管理するアクタ
    private let deviceAuthenticator: AzukiDeviceAuthenticator

    /// リクエストごとの認証要件
    private enum AuthorizationRequirement {
        /// アクセストークン不要
        case none
        /// あれば送るが、無ければそのまま送信
        case optional
        /// 必ずアクセストークンが必要
        case required
    }

    private init(
        session: URLSession = .shared,
        accessTokenStore: AzukiAccessTokenStore = AzukiAccessTokenStore(),
        refreshTokenStore: AzukiRefreshTokenStore = AzukiRefreshTokenStore(),
        deviceAuthenticator: AzukiDeviceAuthenticator = AzukiDeviceAuthenticator()
    ) {
        self.session = session
        let encoder = JSONEncoder()
        
        //encoder.keyEncodingStrategy = .convertToSnakeCase
        // サーバー側のエンドポイントはキャメルケースのキー名を必須としているため、
        // ここでスネークケースへ自動変換してしまうと「Required」エラーが発生する。
        // そのため、エンコード時はキー名を変換せず、定義したプロパティ名をそのまま送信する。
        encoder.keyEncodingStrategy = .useDefaultKeys

        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.accessTokenStore = accessTokenStore
        self.refreshTokenStore = refreshTokenStore
        self.deviceAuthenticator = deviceAuthenticator
    }

    /// OpenAI(azuki-api経由)にパック生成を依頼する
    /// - Parameters:
    ///   - userId: クレジット消費対象となるユーザーID
    ///   - requirement: ユーザーが入力した要件
    ///   - basePack: 修正時、元になるPack
    ///   - isTrial: true=リワード広告視聴後の無料送信
    /// - Returns: PackListへそのまま取り込めるDTO
    func generatePack(userId: String,
                     requirement: String,
                     basePack: PackJsonDTO?,
                     isTrial: Bool = false,
                     languageCode: String?) async throws -> PackJsonDTO {
        struct GenerateRequest: Encodable {
            let userId: String
            let requirement: String
            let basePack: PackJsonDTO?
            // リワード視聴後のお試し送信かどうかを示すフラグ。サーバー側でモデルを選択する
            let isTrial: Bool
            /// ユーザーの端末言語コード（プロンプトに埋め込まずパラメータで渡す）
            let languageCode: String?
        }

        guard let url = makeURL(path: "/api/openai") else {
            throw AzukiAPIError.invalidURL
        }
        // リクエスト パラメータ
        let requestBody = GenerateRequest(userId: userId,
                                          requirement: requirement,
                                          basePack: basePack,
                                          isTrial: isTrial,
                                          languageCode: languageCode)
        let data = try await sendJSONRequest(url: url, body: requestBody, authorization: .required)
        do {
            return try decoder.decode(PackJsonDTO.self, from: data)
        } catch {
            throw AzukiAPIError.decoding
        }
    }

    /// サーバーに保存されている最新のクレジット残高や広告特典の状態を取得する
    /// - Parameter userId: 照会対象のユーザーID
    /// - Returns: クレジット残高と広告特典フラグ
    func fetchCreditStatus(userId: String) async throws -> CreditStatus {
        struct CreditCheckResponse: Decodable {
            let balance: Int
            let adRewardBalance: Int?
            let accessToken: String?
            let accessTokenExpiresAt: Double?
            let refreshToken: String?
            let refreshTokenExpiresAt: Double?
        }

        let queryItems = [URLQueryItem(name: "userId", value: userId)]

        guard let url = makeURL(path: "/api/credit/check", queryItems: queryItems) else {
            throw AzukiAPIError.invalidURL
        }

        // アクセストークン未取得のユーザーにも発行するため、認証ヘッダは任意付与とする
        let request = try await makeRequest(url: url, method: "GET", body: nil, authorization: .optional)

        func decodeCreditStatus(from data: Data) throws -> CreditStatus {
            do {
                let response = try decoder.decode(CreditCheckResponse.self, from: data)
                // サーバーから返却されたトークン群をすべて保存し、後続のリクエストで即利用できるようにする
                storeTokensIfProvided(
                    accessToken: response.accessToken,
                    accessTokenExpiresAt: response.accessTokenExpiresAt,
                    refreshToken: response.refreshToken,
                    refreshTokenExpiresAt: response.refreshTokenExpiresAt
                )
                return CreditStatus(balance: response.balance, adRewardBalance: response.adRewardBalance ?? 0)
            } catch {
                throw AzukiAPIError.decoding
            }
        }

        // refresh API 経由での再送は不要なため、明示的にリフレッシュリトライを抑止する
        // 401 が返った場合だけ Authorization を外して再送する意図
        do {
            let data = try await send(request: request, allowRetryAfterRefresh: false)
            return try decodeCreditStatus(from: data)
        } catch let apiError as AzukiAPIError {
            // 期限切れや無効なAuthorizationヘッダを送ってしまった場合でも、ヘッダを外して再試行し新規発行を促す
            if case .unauthorized = apiError {
                var retryRequest = request
                retryRequest.setValue(nil, forHTTPHeaderField: "Authorization")
                let data = try await send(request: retryRequest, allowRetryAfterRefresh: false)
                return try decodeCreditStatus(from: data)
            }
            throw apiError
        } catch {
            throw error
        }
    }

    struct VerifyPurchaseResult {
        /// サーバーが返した最新残高
        let balance: Int
        /// サーバー側ですでに処理済みだったかどうか
        let duplicate: Bool
    }
    /// StoreKitで購入したトランザクションをサーバーへ通知し、残高を更新してもらう
    /// - Parameters:
    ///   - userId: azuki-apiが管理するユーザー識別子
    ///   - productId: 購入した商品のID
    ///   - transactionId: StoreKitトランザクションのID（重複購入検出に利用）
    ///   - receipt: StoreKitトランザクションのJWS等、サーバーでハッシュ化する生データ
    ///   - grantCredits: 付与予定のクレジット数（サーバー側の定義と一致する必要がある）
    /// - Returns: サーバーが更新した最新残高
    func verifyPurchase(userId: String,
                        productId: String,
                        transactionId: String,
                        receipt: String,
                        storekitJws: String,
                        grantCredits: Int) async throws -> VerifyPurchaseResult {
        struct VerifyRequest: Encodable {
            let userId: String
            let productId: String
            let transactionId: String
            let receipt: String
            let storekitJws: String
            let grantCredits: Int
            let deviceId: String
            let devicePublicKey: String
            let attestKeyId: String
            let attestation: String
            let attestationChallenge: String
        }

        struct VerifyResponse: Decodable {
            let balance: Int
            let duplicate: Bool?
            let accessToken: String?
            let accessTokenExpiresAt: Double?
            let refreshToken: String?
            let refreshTokenExpiresAt: Double?
        }

        guard let url = makeURL(path: "/api/iap/verify") else {
            throw AzukiAPIError.invalidURL
        }

        // App Attest を通過した端末情報を取得し、サーバーへ同封する
        let identity: AzukiDeviceAuthenticator.DeviceIdentity
        do {
            identity = try await deviceAuthenticator.ensureIdentity()
        } catch let error as AzukiDeviceAuthenticator.AuthenticatorError {
            switch error {
            case .unsupported:
                throw AzukiAPIError.deviceSecurityUnavailable
            default:
                throw AzukiAPIError.deviceSignatureFailed
            }
        } catch {
            throw AzukiAPIError.deviceSignatureFailed
        }
        
        // ログイン/ユーザー判明時や状態変化時に設定
        Analytics.setUserID(userId)                 // 任意のユーザーID
        //Analytics.setUserProperty("pro", forName: "plan") // "free"/"pro"
        //Analytics.setUserProperty("ja-JP", forName: "locale")
        Analytics.setUserProperty("ios", forName: "platform")
        
        let body = VerifyRequest(
            userId: userId,
            productId: productId,
            transactionId: transactionId,
            receipt: receipt,
            storekitJws: storekitJws,
            grantCredits: grantCredits,
            deviceId: identity.deviceId,
            devicePublicKey: identity.devicePublicKey,
            attestKeyId: identity.attestKeyId,
            attestation: identity.attestation,
            attestationChallenge: identity.attestationChallenge
        )
        let data = try await sendJSONRequest(url: url, body: body, authorization: .optional)
        do {
            let response = try decoder.decode(VerifyResponse.self, from: data)
            // サーバーが返却するトークン群をまとめて保存し、後続の API リクエストに備える
            storeTokensIfProvided(
                accessToken: response.accessToken,
                accessTokenExpiresAt: response.accessTokenExpiresAt,
                refreshToken: response.refreshToken,
                refreshTokenExpiresAt: response.refreshTokenExpiresAt
            )
            return VerifyPurchaseResult(balance: response.balance, duplicate: response.duplicate ?? false)
        } catch {
            throw AzukiAPIError.decoding
        }
    }

    /// 相対パスからURLを構築し、必要であればクエリを付与する
    private func makeURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        guard let baseURL = URL(string: path, relativeTo: AZUKI_API_BASE_URL) else {
            return nil
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            return nil
        }
        if let queryItems = queryItems, queryItems.isEmpty == false {
            components.queryItems = queryItems
        }
        return components.url
    }

    /// 共通のJSON POST送信をまとめ、認証ヘッダの付与やエンコードを一括で行う
    private func sendJSONRequest<T: Encodable>(url: URL, body: T, authorization: AuthorizationRequirement) async throws -> Data {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            throw AzukiAPIError.encoding
        }

        let request = try await makeRequest(url: url, method: "POST", body: payload, authorization: authorization)
        return try await send(request: request)
    }

    /// 認証ヘッダやAcceptヘッダを共通設定する
    private func makeRequest(url: URL, method: String, body: Data?, authorization: AuthorizationRequirement) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        switch authorization {
        case .none:
            break
        case .optional:
            // 端末に保存済みのトークンがあれば付与し、初回購入前など未取得ならそのまま送信する
            if let token = accessTokenStore.currentTokenIfValid() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .required:
            // 認証必須のエンドポイントではKeychainに無ければ復旧ハンドラを呼び出してから判定する
            let token = try await obtainValidAccessTokenForRequiredRequest()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    /// サーバーから受け取ったトークン情報をまとめて保存し、再利用できるようにする
    /// - Parameters:
    ///   - accessToken: 新しいアクセストークン（nil の場合はスキップ）
    ///   - accessTokenExpiresAt: アクセストークンの有効期限（ミリ秒）
    ///   - refreshToken: 新しいリフレッシュトークン（nil の場合はスキップ）
    ///   - refreshTokenExpiresAt: リフレッシュトークンの有効期限（ミリ秒）
    private func storeTokensIfProvided(
        accessToken: String?,
        accessTokenExpiresAt: Double?,
        refreshToken: String?,
        refreshTokenExpiresAt: Double?
    ) {
        if let token = accessToken, let expiresAt = accessTokenExpiresAt {
            accessTokenStore.save(token: token, expiresAtMilliseconds: expiresAt)
        }
        if let refresh = refreshToken, let refreshExpiresAt = refreshTokenExpiresAt {
            refreshTokenStore.save(token: refresh, expiresAtMilliseconds: refreshExpiresAt)
        }
    }

    /// Keychainに有効なアクセストークンが保持されているかを確認する
    /// - Returns: 有効期限内のアクセストークンがあれば true
    func hasValidAccessToken() -> Bool {
        guard let token = accessTokenStore.currentTokenIfValid() else {
            return false
        }
        return token.isEmpty == false
    }

    /// 認証必須リクエスト向けに有効なアクセストークンを確保する
    /// - Returns: Authorizationヘッダへ設定すべきトークン文字列
    private func obtainValidAccessTokenForRequiredRequest() async throws -> String {
        // まずはKeychainに既に有効なトークンがあるかを確認する
        if let token = accessTokenStore.currentTokenIfValid() {
            return token
        }

        // アクセストークンが切れていてもリフレッシュトークンが残っていれば自動で更新を試みる
        if let refreshed = try await refreshAccessTokenIfPossible() {
            return refreshed
        }

        // ビュー層が登録した復旧ハンドラがあれば一度だけ呼び出してみる
        if let handler = await tokenRecoveryHandlerBox.currentHandler() {
            // 復旧ハンドラがtrueを返すかどうかに関係なく、Keychainへ再保存されたかを必ず確認する
            // （古いバージョンのハンドラが常にfalseを返す既知の挙動に備えるため）
            let didRecover = await handler()
            // 復旧結果のフラグはデバッグ用に保持しておきつつ、実際にはKeychainの再確認を優先する
            if let refreshed = accessTokenStore.currentTokenIfValid() {
                return refreshed
            }
            // ハンドラがtrueを返したのにKeychainへ何も保存されていない場合は想定外なので、開発中に気付けるようアサーションを置いておく
            if didRecover {
                assertionFailure("Token recovery handler reported success but no token was stored.")
            }
        }

        // ここまででトークンが得られなければ従来通りエラーを投げ、上位へリカバリを委ねる
        throw AzukiAPIError.missingAuthToken
    }

    /// 保存済みのリフレッシュトークンを利用してアクセストークンを再発行する
    /// - Returns: 新しいアクセストークン（更新に失敗した場合は nil）
    private func refreshAccessTokenIfPossible() async throws -> String? {
        try await refreshCoordinator.refresh {
            if let existing = self.accessTokenStore.currentTokenIfValid() {
                return existing
            }
            guard let refreshToken = self.refreshTokenStore.currentTokenIfValid() else {
                return nil
            }
            guard let url = self.makeURL(path: "/api/auth/refresh") else {
                throw AzukiAPIError.invalidURL
            }
            // サーバーへ端末IDを提示できなければリフレッシュ要件を満たせないため、そのまま終了する
            guard let identity = await self.deviceAuthenticator.currentIdentity() else {
                return nil
            }

            struct StageOneRequest: Encodable {
                let refreshToken: String
                let deviceId: String
            }

            let firstPayload: Data
            do {
                // 第1段階ではリフレッシュトークンと端末IDのみを送信し、チャレンジ発行を促す
                firstPayload = try self.encoder.encode(StageOneRequest(refreshToken: refreshToken, deviceId: identity.deviceId))
            } catch {
                throw AzukiAPIError.encoding
            }

            func buildRequest(body: Data) -> URLRequest {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                return request
            }

            let firstRequest = buildRequest(body: firstPayload)
            let firstResult: (data: Data, response: URLResponse)
            do {
                firstResult = try await self.session.data(for: firstRequest)
            } catch {
                throw error
            }

            guard let firstHTTP = firstResult.response as? HTTPURLResponse else {
                throw AzukiAPIError.invalidResponse
            }
            let firstStatus = firstHTTP.statusCode

            struct RefreshResponse: Decodable {
                let stage: String?
                let userId: String
                let accessToken: String
                let accessTokenExpiresAt: Double
                let refreshToken: String
                let refreshTokenExpiresAt: Double
            }

            struct RefreshChallengeEnvelope: Decodable {
                let stage: String
                let challengeId: String
                let nonce: String
                let expiresAt: Double?
            }

            func handleSuccess(data: Data) throws -> String {
                // デコード処理が失敗した場合に備えて、try? で明示的に失敗を検出する
                guard let decoded = try? self.decoder.decode(RefreshResponse.self, from: data) else {
                    // 期待したレスポンス形式と異なる場合はデコードエラーとして扱う
                    throw AzukiAPIError.decoding
                }
                self.storeTokensIfProvided(
                    accessToken: decoded.accessToken,
                    accessTokenExpiresAt: decoded.accessTokenExpiresAt,
                    refreshToken: decoded.refreshToken,
                    refreshTokenExpiresAt: decoded.refreshTokenExpiresAt
                )
                return decoded.accessToken
            }

            func handleFailure(status: Int, data: Data) async throws -> String? {
                let serverErrorCode = self.decodeServerErrorCode(from: data)
                if status == 401 || status == 400 {
                    if serverErrorCode == "invalid_refresh_token" || serverErrorCode == "refresh_token_expired" {
                        self.refreshTokenStore.clear()
                        self.accessTokenStore.clear()
                        // トークンが失効している場合、端末鍵も再登録が必要となるため一緒に破棄する
                        await self.deviceAuthenticator.invalidateIdentity()
                        return nil
                    }
                    if serverErrorCode == "device_revoked" || serverErrorCode == "invalid_device" || serverErrorCode == "challenge_failed" {
                        self.refreshTokenStore.clear()
                        self.accessTokenStore.clear()
                        // サーバーから端末失効が通知されたケース。再アテステーションを促すために端末情報も消す
                        await self.deviceAuthenticator.invalidateIdentity()
                        return nil
                    }
                }
                if status == 401 { // Unauthorized  アクセス権が無い、または認証に失敗
                    return nil
                }
                if status == 404 { // Not Found Webページが見つからない
                    throw AzukiAPIError.server(statusCode: status)
                }
                throw AzukiAPIError.server(statusCode: status)
            }

            if 199 < firstStatus && firstStatus < 300 {
                if let challenge = try? self.decoder.decode(RefreshChallengeEnvelope.self, from: firstResult.data), challenge.stage == "challenge" {
                    let signaturePayload: AzukiDeviceAuthenticator.RefreshSignaturePayload
                    do {
                        // 付与されたノンスとトークンをまとめて署名し、サーバーへ再提出する
                        signaturePayload = try await self.deviceAuthenticator.signRefreshChallenge(nonce: challenge.nonce, refreshToken: refreshToken)
                    } catch let authError as AzukiDeviceAuthenticator.AuthenticatorError {
                        switch authError {
                        case .unsupported:
                            throw AzukiAPIError.deviceSecurityUnavailable
                        default:
                            throw AzukiAPIError.deviceSignatureFailed
                        }
                    } catch {
                        throw AzukiAPIError.deviceSignatureFailed
                    }

                    struct StageTwoRequest: Encodable {
                        let refreshToken: String
                        let deviceId: String
                        let challengeId: String
                        let nonce: String
                        let signature: String
                        let signedAt: String
                        let refreshTokenHash: String
                    }

                    let stageTwoBody: Data
                    do {
                        // 第2段階ではチャレンジIDや署名済み情報をまとめて送信し、新しいトークン群を要求する
                        stageTwoBody = try self.encoder.encode(
                            StageTwoRequest(
                                refreshToken: refreshToken,
                                deviceId: identity.deviceId,
                                challengeId: challenge.challengeId,
                                nonce: challenge.nonce,
                                signature: signaturePayload.signature,
                                signedAt: signaturePayload.signedAt,
                                refreshTokenHash: signaturePayload.refreshTokenHash
                            )
                        )
                    } catch {
                        throw AzukiAPIError.encoding
                    }

                    let secondRequest = buildRequest(body: stageTwoBody)
                    let secondResult: (data: Data, response: URLResponse)
                    do {
                        secondResult = try await self.session.data(for: secondRequest)
                    } catch {
                        throw error
                    }
                    guard let secondHTTP = secondResult.response as? HTTPURLResponse else {
                        throw AzukiAPIError.invalidResponse
                    }
                    let secondStatus = secondHTTP.statusCode
                    if 199 < secondStatus && secondStatus < 300 {
                        return try handleSuccess(data: secondResult.data)
                    }
                    return try await handleFailure(status: secondStatus, data: secondResult.data)
                }
                return try handleSuccess(data: firstResult.data)
            }

            return try await handleFailure(status: firstStatus, data: firstResult.data)
        }
    }

    /// トークン復旧ハンドラを登録する
    /// - Parameter handler: Keychainへ新しいトークンを書き込むことを期待する非同期処理
    func registerTokenRecoveryHandler(_ handler: @escaping () async -> Bool) async {
        await tokenRecoveryHandlerBox.update(handler: handler)
    }

    /// 登録済みのトークン復旧ハンドラを破棄する
    func clearTokenRecoveryHandler() async {
        await tokenRecoveryHandlerBox.update(handler: nil)
    }

    /// デバッグ操作などで userId をリセットした際に、古いユーザーに紐づく認証情報を捨てる
    /// - Note: Keychain を手動削除したあとに再度購入テストを行うとき、旧トークンが残っていると `401-forbiddenUser` に繋がるため、明示的にリセットする
    func clearAuthenticationStateForUserReset() {
        // 購入直前に userId が空から復旧した場合は、古いユーザー向けのトークンを持っていても再利用しない
        accessTokenStore.clear()
        refreshTokenStore.clear()
    }

    /// 実際の通信と共通エラーハンドリングを一箇所へ集約
    private func send(request: URLRequest, allowRetryAfterRefresh: Bool = true) async throws -> Data {
        do {
            // URLSession.data(for:) は内部でTask.cancelledを投げることがあるため、do-catchでまとめて扱う
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AzukiAPIError.invalidResponse
            }
            let status = httpResponse.statusCode
            if status == 402 {
                throw AzukiAPIError.insufficientCredits
            }
            if status == 401 {
                let serverErrorCode = decodeServerErrorCode(from: data)
                let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
                let isRefreshEndpoint = request.url?.path == "/api/auth/refresh"
                if allowRetryAfterRefresh,
                   authorization.isEmpty == false,
                   isRefreshEndpoint == false,
                   let refreshed = try await refreshAccessTokenIfPossible() {
                    var retriedRequest = request
                    retriedRequest.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
                    return try await send(request: retriedRequest, allowRetryAfterRefresh: false)
                }
                // サーバー側でアクセストークンが拒否されたため、Keychainに残っている値も破棄する
                accessTokenStore.clear()
                if serverErrorCode == "invalid_refresh_token" || serverErrorCode == "refresh_token_expired" {
                    refreshTokenStore.clear()
                }
                if serverErrorCode == "device_revoked" || serverErrorCode == "invalid_device" || serverErrorCode == "challenge_failed" {
                    // 端末側の鍵ペアに問題があると判断できるため、再アテステーションを促す
                    refreshTokenStore.clear()
                    await deviceAuthenticator.invalidateIdentity()
                }
                if serverErrorCode == "token_expired" {
                    throw AzukiAPIError.tokenExpired
                }
                throw AzukiAPIError.unauthorized
            }
            if status == 403 {
                let serverErrorCode = decodeServerErrorCode(from: data)
                if serverErrorCode == "receipt_belongs_to_other_user" {
                    throw AzukiAPIError.receiptBelongsToOtherUser
                }
                throw AzukiAPIError.forbiddenUser
            }
            // Hono（Cloudflare Workers）からの2xxレスポンスのみ成功扱いとし、それ以外は個別にハンドリングする
            if 199 < status && status < 300 {
                return data
            }

            let serverErrorCode = decodeServerErrorCode(from: data)
            if status == 409 && serverErrorCode == "duplicate_transaction" {
                throw AzukiAPIError.duplicateTransaction
            }
            if status == 400 {
                if serverErrorCode == "unknown_product" {
                    throw AzukiAPIError.unknownProduct
                }
                else if serverErrorCode == "mismatched_grant" {
                    throw AzukiAPIError.purchaseMismatch
                }
            }
            if let msg = serverErrorCode {
                throw AzukiAPIError.serverError(message: msg)
            }
            //throw AzukiAPIError.server(statusCode: status)
            throw AzukiAPIError.serverError(message: "(\(status))" + httpResponse.description)
        } catch let error as AzukiAPIError {
            throw error
        } catch {
            throw error
        }
    }

    /// サーバーからのエラーレスポンスに含まれる`error`キーを取り出して再利用する
    private func decodeServerErrorCode(from data: Data) -> String? {
        if data.isEmpty {
            return nil
        }
        struct ServerError: Decodable {
            let error: String
        }
        if let decoded = try? decoder.decode(ServerError.self, from: data), decoded.error.isEmpty == false {
            return decoded.error
        }
        if let fallback = String(data: data, encoding: .utf8), fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

/// トークン復旧ハンドラを安全に保持・更新するためのアクタ
private actor TokenRecoveryHandlerBox {
    /// 現在登録されている復旧ハンドラ。nilなら復旧不能を意味する。
    private var handler: (() async -> Bool)?

    /// 現在のハンドラを読み出す
    func currentHandler() -> (() async -> Bool)? {
        handler
    }

    /// 新しいハンドラを登録または破棄する
    /// - Parameter handler: 代入したいハンドラ。nilを渡すと破棄。
    func update(handler: (() async -> Bool)?) {
        self.handler = handler
    }
}

/// リフレッシュ API の多重実行を防ぎ、最新トークンを一貫して配布するためのアクタ
private actor RefreshCoordinator {
    /// 進行中のリフレッシュ処理を共有するための Task
    private var currentTask: Task<String?, Error>?

    /// 与えられたリフレッシュ処理を直列化して実行する
    /// - Parameter operation: リフレッシュ API を呼び出す非同期処理
    /// - Returns: 処理が返したアクセストークン（または nil）
    func refresh(using operation: @escaping () async throws -> String?) async throws -> String? {
        if let task = currentTask {
            return try await task.value
        }
        let task = Task {
            try await operation()
        }
        currentTask = task
        defer {
            currentTask = nil
        }
        return try await task.value
    }
}
