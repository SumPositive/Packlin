//
//  AzukiAPIClient.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import Foundation

/// azuki-api と通信する責務を担うクライアント
/// - APIの仕様は Cloudflare Workers + Neon (PostgreSQL) 上の TypeScript 実装に準拠する
/// - アプリ側では UUID を端末ごとに払い出し userId として使い回す
/// - JSON デコードでは createdAt が数値(UNIX秒)と文字列(ISO8601)のどちらでも受け取れるよう配慮する
final class AzukiAPIClient {
    /// シングルトン。設定値を変えたい場合は別途イニシャライザを利用する
    static let shared = AzukiAPIClient()

    /// ユーザーIDを保存する UserDefaults のキー
    private let userIdDefaultsKey = "AzukiAPIClient.userId"
    /// API ベースURL。Info.plist の `AzukiAPIBaseURL` が指定されていればそれを利用
    private let baseURL: URL
    /// 通信に利用する URLSession
    private let session: URLSession
    /// JSONデコード用の Decoder。createdAt の形式差異に対応済み
    private let decoder: JSONDecoder
    /// JSONエンコード用の Encoder
    private let encoder: JSONEncoder
    /// ユーザーIDを永続化する UserDefaults
    private let defaults: UserDefaults

    /// ISO8601 の日付解析に利用するフォーマッタ（小数秒あり・なし両対応）
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Info.plist からベースURLを解決し、未設定なら既定値を採用
    private static func resolveBaseURL() -> URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "AzukiAPIBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false, let url = URL(string: trimmed) {
                return url
            }
        }
        // 既定値。必要に応じて Info.plist の AzukiAPIBaseURL で上書きする想定
        return URL(string: "https://azuki-api.azukid.com")!
    }

    /// `Date` デコード戦略。UNIX秒(数値)とISO8601(文字列)双方を許容する
    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: doubleValue)
        }
        if let intValue = try? container.decode(Int.self) {
            let interval = TimeInterval(intValue)
            return Date(timeIntervalSince1970: interval)
        }
        let stringValue = try container.decode(String.self)
        if let date = isoFormatter.date(from: stringValue) {
            return date
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "createdAt を Date として解釈できませんでした"
            )
        )
    }

    /// APIが返すエラーレスポンスの基本形
    private struct ErrorEnvelope: Decodable {
        let error: String
        let detail: String?
        let status: Int?
    }

    /// /api/credit/check のレスポンス
    struct CreditBalance: Decodable {
        let userId: String
        let balance: Int
    }

    /// クライアント側で扱うエラー表現
    enum APIError: LocalizedError {
        case invalidConfiguration
        case network(Error)
        case invalidResponse
        case insufficientCredits
        case server(message: String, statusCode: Int)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                return "APIの設定値が正しくありません。Info.plist の AzukiAPIBaseURL を確認してください。"
            case .network(let error):
                return "通信に失敗しました: \(error.localizedDescription)"
            case .invalidResponse:
                return "サーバーからのレスポンスが不正でした。"
            case .insufficientCredits:
                return "クレジットが不足しています。チャージ後に再試行してください。"
            case .server(let message, let statusCode):
                return "サーバー側でエラーが発生しました(\(statusCode)): \(message)"
            case .decoding:
                return "サーバーから受け取ったデータを解析できませんでした。"
            }
        }
    }

    /// 依存関係を注入できるイニシャライザ
    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.baseURL = baseURL ?? AzukiAPIClient.resolveBaseURL()
        self.session = session
        self.defaults = defaults

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(AzukiAPIClient.decodeDate)
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        self.encoder = encoder
    }

    /// 端末ごとに固定の userId を払い出す（存在しなければ生成）
    private func currentUserId() -> String {
        if let saved = defaults.string(forKey: userIdDefaultsKey), saved.isEmpty == false {
            return saved
        }
        let newValue = UUID().uuidString.lowercased()
        defaults.set(newValue, forKey: userIdDefaultsKey)
        return newValue
    }

    /// 指定パスに対する URLRequest を生成
    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidConfiguration
        }
        if let queryItems {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// 実際に通信を行い、HTTPURLResponse と Data を返す
    private func fetchData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            return (data, httpResponse)
        } catch {
            throw APIError.network(error)
        }
    }

    /// クレジット残高を取得
    func fetchCreditBalance() async throws -> CreditBalance {
        let userId = currentUserId()
        let request = try makeRequest(
            path: "api/credit/check",
            method: "GET",
            queryItems: [URLQueryItem(name: "userId", value: userId)]
        )
        let (data, response) = try await fetchData(for: request)
        if response.statusCode < 200 || 300 <= response.statusCode {
            let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
            let message = envelope?.detail ?? envelope?.error ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw APIError.server(message: message, statusCode: response.statusCode)
        }
        do {
            return try decoder.decode(CreditBalance.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// OpenAI 経由でパック生成を依頼し、PackJsonDTO を受け取る
    func requestPack(requirement: String) async throws -> PackJsonDTO {
        struct OpenAIRequest: Encodable {
            let userId: String
            let requirement: String
        }
        let payload = OpenAIRequest(userId: currentUserId(), requirement: requirement)
        let bodyData = try encoder.encode(payload)
        let request = try makeRequest(
            path: "api/openai",
            method: "POST",
            body: bodyData
        )
        let (data, response) = try await fetchData(for: request)
        if response.statusCode < 200 || 300 <= response.statusCode {
            let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
            if response.statusCode == 402, envelope?.error == "insufficient_credits" {
                throw APIError.insufficientCredits
            }
            let message = envelope?.detail ?? envelope?.error ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw APIError.server(message: message, statusCode: response.statusCode)
        }
        do {
            return try decoder.decode(PackJsonDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
