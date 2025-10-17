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

    private init(session: URLSession = .shared) {
        self.session = session
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
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
        let data = try await sendRequest(url: url, body: requestBody)
        do {
            return try decoder.decode(PackJsonDTO.self, from: data)
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

    /// 共通のPOST送信をまとめる。StoreKitレシートなど追加データが必要になってもここでまとめて処理可能
    private func sendRequest<T: Encodable>(url: URL, body: T) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw AzukiAPIError.encoding
        }
        return try await send(request: request)
    }

    /// 実際の通信と共通エラーハンドリングを一箇所へ集約
    private func send(request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AzukiAPIError.invalidResponse
            }
            if httpResponse.statusCode == 402 {
                throw AzukiAPIError.insufficientCredits
            }
            if httpResponse.statusCode <= 199 || 300 <= httpResponse.statusCode {
                throw AzukiAPIError.server(statusCode: httpResponse.statusCode)
            }
            return data
        } catch let error as AzukiAPIError {
            throw error
        } catch {
            throw error
        }
    }
}
