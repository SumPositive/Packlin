//
//  AzukiAPIClient.swift
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
    case decoding
    case encoding
    case insufficientCredits
    case missingAuthToken
    case unauthorized
    case forbiddenUser
    case duplicateTransaction
    case unknownProduct
    case purchaseMismatch

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "サーバーのURLを組み立てられませんでした。時間をおいて再度お試しください。")
        case .invalidResponse:
            return String(localized: "サーバーの応答が不正でした。通信状況をご確認ください。")
        case .server(let statusCode):
            return String(localized: "サーバーエラー") + "(\(statusCode))"
                + String(localized: "が発生しました。サポートへお問い合わせください。")
        case .decoding:
            return String(localized: "サーバーから受信したデータを解析できませんでした。")
        case .encoding:
            return String(localized: "送信データの準備に失敗しました。入力内容をご確認ください。")
        case .insufficientCredits:
            return String(localized: "クレジットが不足しています。購入後に再度お試しください。")
        case .missingAuthToken:
            return String(localized: "認証情報が設定されていません。アプリを再インストールするかサポートへお問い合わせください。")
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
    /// JWTでの認証に使用するトークン（Info.plistや環境変数から読み込む想定）
    private let authToken: String

    private init(session: URLSession = .shared, authToken: String = AZUKI_API_AUTH_JWT) {
        self.session = session
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.authToken = authToken
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
        let data = try await sendJSONRequest(url: url, body: requestBody)
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

        let request = try makeAuthorizedRequest(url: url, method: "GET")
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
    func verifyPurchase(userId: String, productId: String, transactionId: String, receipt: String, grantCredits: Int) async throws -> Int {
        struct VerifyRequest: Encodable {
            let userId: String
            let productId: String
            let transactionId: String
            let receipt: String
            let grantCredits: Int
        }

        struct VerifyResponse: Decodable {
            let balance: Int
        }

        guard let url = makeURL(path: "/api/iap/verify") else {
            throw AzukiAPIError.invalidURL
        }

        let body = VerifyRequest(userId: userId, productId: productId, transactionId: transactionId, receipt: receipt, grantCredits: grantCredits)
        let data = try await sendJSONRequest(url: url, body: body)
        do {
            let response = try decoder.decode(VerifyResponse.self, from: data)
            return response.balance
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
    private func sendJSONRequest<T: Encodable>(url: URL, body: T) async throws -> Data {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            throw AzukiAPIError.encoding
        }

        let request = try makeAuthorizedRequest(url: url, method: "POST", body: payload)
        return try await send(request: request)
    }

    /// 認証ヘッダやAcceptヘッダを共通設定する
    private func makeAuthorizedRequest(url: URL, method: String, body: Data? = nil) throws -> URLRequest {
        // Info.plistや環境変数から取得したJWTを都度クレンジングして利用する
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.isEmpty {
            throw AzukiAPIError.missingAuthToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// 実際の通信と共通エラーハンドリングを一箇所へ集約
    private func send(request: URLRequest) async throws -> Data {
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
                throw AzukiAPIError.unauthorized
            }
            if status == 403 {
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
                if serverErrorCode == "mismatched_grant" {
                    throw AzukiAPIError.purchaseMismatch
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
