//
//  AzukiAPIClient.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
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
            return "サーバーのURLを組み立てられませんでした。時間をおいて再度お試しください。"
        case .invalidResponse:
            return "サーバーの応答が不正でした。通信状況をご確認ください。"
        case .server(let statusCode):
            return "サーバーエラー(\(statusCode))が発生しました。サポートへお問い合わせください。"
        case .decoding:
            return "サーバーから受信したデータを解析できませんでした。"
        case .encoding:
            return "送信データの準備に失敗しました。入力内容をご確認ください。"
        case .insufficientCredits:
            return "クレジットが不足しています。購入後に再度お試しください。"
        }
    }
}

/// azuki-api との通信を担うクライアント
/// - Note: iOS側では決済処理そのものはStoreKit任せとし、azuki-apiはレシート検証とOpenAI代理実行を提供する想定
final class AzukiAPIClient {
    static let shared = AzukiAPIClient()

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

    /// 最小課金（3クレジット追加）を実行する
    /// - Returns: 追加されたクレジット数
    func purchaseMinimumCredits() async throws -> Int {
        struct PurchaseRequest: Encodable {
            let productId: String
        }
        struct PurchaseResponse: Decodable {
            let creditsAdded: Int
        }

        guard let url = URL(string: "iap/purchase", relativeTo: AZUKI_API_BASE_URL) else {
            throw AzukiAPIError.invalidURL
        }

        let requestBody = PurchaseRequest(productId: AZUKI_API_MIN_CONSUMABLE_PRODUCT_ID)
        let data = try await sendRequest(url: url, body: requestBody)
        do {
            let response = try decoder.decode(PurchaseResponse.self, from: data)
            return response.creditsAdded
        } catch {
            throw AzukiAPIError.decoding
        }
    }

    /// OpenAI(azuki-api経由)にパック生成を依頼する
    /// - Parameter requirement: ユーザーが入力した要件
    /// - Returns: PackListへそのまま取り込めるDTO
    func generatePack(requirement: String) async throws -> PackJsonDTO {
        struct GenerateRequest: Encodable {
            let requirement: String
            let model: String
        }
        struct GenerateResponse: Decodable {
            let pack: PackJsonDTO
        }

        guard let url = URL(string: "openai/generate-pack", relativeTo: AZUKI_API_BASE_URL) else {
            throw AzukiAPIError.invalidURL
        }

        let requestBody = GenerateRequest(requirement: requirement, model: OPENAI_CHAT_COMPLETION_MODEL)
        let data = try await sendRequest(url: url, body: requestBody)
        do {
            let response = try decoder.decode(GenerateResponse.self, from: data)
            return response.pack
        } catch {
            throw AzukiAPIError.decoding
        }
    }

    /// 共通のPOST送信をまとめる。StoreKitレシートなど追加データが必要になってもここでまとめて処理可能
    private func sendRequest<T: Encodable>(url: URL, body: T) async throws -> Data {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AzukiAPIError.invalidResponse
            }
            if httpResponse.statusCode < 200 || 299 < httpResponse.statusCode {
                throw AzukiAPIError.server(statusCode: httpResponse.statusCode)
            }
            return data
        } catch let error as AzukiAPIError {
            throw error
        } catch is EncodingError {
            throw AzukiAPIError.encoding
        } catch {
            throw error
        }
    }
}
