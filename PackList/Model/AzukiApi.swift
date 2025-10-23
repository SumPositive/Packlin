//
//  AzukiApi.swift
//  PackList
//
//  Created by sumpo on 2025/10/12.
//

import Foundation

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

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "サーバーのURLを組み立てられませんでした。時間をおいて再度お試しください。")
        case .invalidResponse:
            return String(localized: "サーバーの応答が不正でした。通信状況をご確認ください。")
        case .server(let statusCode):
            return String(localized: "サーバーエラー") + "(\(statusCode))"
                + String(localized: "が発生しました。サポートへお問い合わせください。")
        case .serverError(let message):
                return String(localized: "サーバーエラー") + "「\(message)」"
                + String(localized: "が発生しました。サポートへお問い合わせください。")
        case .decoding:
            return String(localized: "サーバーから受信したデータを解析できませんでした。")
        case .encoding:
            return String(localized: "送信データの準備に失敗しました。入力内容をご確認ください。")
        case .insufficientCredits:
            return String(localized: "クレジットが不足しています。購入後に再度お試しください。")
        case .missingAuthToken:
            return String(localized: "アクセストークンが見つかりません。購入履歴を復元してから再度お試しください。")
        case .unauthorized:
            return String(localized: "認証に失敗しました。通信状況を確認しても解決しない場合はサポートへご連絡ください。")
        case .forbiddenUser:
            return String(localized: "ユーザー情報の検証に失敗しました。サポートへお問い合わせください。")
        case .duplicateTransaction:
            return String(localized: "この購入はすでに処理済みです。反映済みかをご確認ください。")
        case .unknownProduct:
            return String(localized: "サーバー側の商品の登録と一致しません。アプリを最新に更新してからお試しください。")
        case .purchaseMismatch:
            return String(localized: "購入情報の整合性を確認できませんでした。時間をおいて再度お試しください。")
        case .tokenExpired:
            return String(localized: "アクセストークンの有効期限が切れました。購入履歴の復元を行ってください。")
        case .receiptBelongsToOtherUser:
            return String(localized: "この購入情報は別のユーザーに紐づいています。サポートへお問い合わせください。")
        case .deviceSecurityUnavailable:
            return String(localized: "端末のセキュリティ機能を利用できません。最新のiOSへ更新後、再度お試しください。")
        case .deviceSignatureFailed:
            return String(localized: "端末認証に失敗しました。アプリを再起動してから再度お試しください。")
        }
    }
}

/// azuki-api との通信を担うクライアント
/// - Note: iOS側では決済処理そのものはStoreKit任せとし、azuki-apiはレシート検証とOpenAI代理実行を提供する想定
final class AzukiApi {
    static let shared = AzukiApi()

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
    /// - Returns: PackListへそのまま取り込めるDTO
    func generatePack(userId: String, requirement: String) async throws -> PackJsonDTO {
        struct GenerateRequest: Encodable {
            let userId: String
            let requirement: String
        }

        guard let url = makeURL(path: "/api/openai") else {
            throw AzukiAPIError.invalidURL
        }

        let requestBody = GenerateRequest(userId: userId, requirement: requirement)
        let data = try await sendJSONRequest(url: url, body: requestBody, authorization: .required)
        do {
            return try decoder.decode(PackJsonDTO.self, from: data)
        } catch {
            throw AzukiAPIError.decoding
        }
    }

    /// サーバーに保存されている最新のクレジット残高を取得し、Keychainと突き合わせるために利用する
    /// - Parameter userId: 照会対象のユーザーID（JWTで本人確認される）
    /// - Returns: サーバーが保持する残高
    func fetchCreditBalance(userId: String) async throws -> Int {
        struct CreditCheckResponse: Decodable {
            let balance: Int
        }

        // Hono側でJWTとuserIdの整合性をチェックするため、クエリにもuserIdを明示的に付与する
        guard let url = makeURL(path: "/api/credit/check", queryItems: [URLQueryItem(name: "userId", value: userId)]) else {
            throw AzukiAPIError.invalidURL
        }

        let request = try await makeRequest(url: url, method: "GET", body: nil, authorization: .required)
        let data = try await send(request: request)
        do {
            let response = try decoder.decode(CreditCheckResponse.self, from: data)
            return response.balance
        } catch {
            throw AzukiAPIError.decoding
        }
    }

    /// StoreKitで購入したトランザクションをサーバーへ通知し、残高を更新してもらう
    /// - Parameters:
    ///   - userId: azuki-apiが管理するユーザー識別子
    ///   - productId: 購入した商品のID
    ///   - transactionId: StoreKitトランザクションのID（重複購入検出に利用）
    ///   - receipt: StoreKitトランザクションのJWS等、サーバーでハッシュ化する生データ
    ///   - grantCredits: 付与予定のクレジット数（サーバー側の定義と一致する必要がある）
    /// - Returns: サーバーが更新した最新残高
    struct VerifyPurchaseResult {
        /// サーバーが返した最新残高
        let balance: Int
        /// サーバー側ですでに処理済みだったかどうか
        let duplicate: Bool
    }

    func verifyPurchase(userId: String, productId: String, transactionId: String, receipt: String, storekitJws: String, grantCredits: Int) async throws -> VerifyPurchaseResult {
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
                let decoded: RefreshResponse
                do {
                    // トークン払い出し成功時は新しいトークン群をKeychainへ即座に保存する
                    decoded = try self.decoder.decode(RefreshResponse.self, from: data)
                } catch {
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
                if status == 401 {
                    return nil
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
                else if let msg = serverErrorCode {
                    throw AzukiAPIError.serverError(message: msg)
                }
            }
            throw AzukiAPIError.server(statusCode: status)
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
