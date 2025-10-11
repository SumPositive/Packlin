//
//  OpenAIPackGenerator.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import Foundation

/// OpenAI APIを利用してPackList向けのパックJSONを生成する担当クラス
struct OpenAIPackGenerator {
    /// OpenAI APIキー（`Bearer`トークン）
    let apiKey: String
    /// 利用するモデル名。標準ではgpt-4.1-miniを指定。
    var model: String = "gpt-4.1-mini"
    /// 実行時に利用するURLSession（テスト差し替えしやすいよう外部注入可能にする）
    var session: URLSession = .shared

    /// OpenAI APIで使用するシステムメッセージ
    private static let systemPrompt: String = {
        """
        あなたはiOSアプリ「PackList」用の荷物リストを生成する専門アシスタントです。
        指示に従って有効なJSONオブジェクトのみを返してください。
        余計な説明やマークダウンは不要です。
        """
    }()

    /// OpenAI APIのエンドポイント
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// 指定された要件に沿って`PackJsonDTO`を生成
    /// - Parameter prompt: ユーザー要件や制約をまとめたプロンプト
    /// - Returns: OpenAIが出力したJSONをデコードした`PackJsonDTO`
    func generatePack(using prompt: String) async throws -> PackJsonDTO {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.2,
            responseFormat: .jsonObject
        )

        let encoder = JSONEncoder()
        let requestData = try encoder.encode(body)
        request.httpBody = requestData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeneratorError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data).error {
                throw GeneratorError.server(message: apiError.message)
            }
            throw GeneratorError.server(message: "HTTPステータス: \(httpResponse.statusCode)")
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let rawContent = completion.choices.first?.message.content else {
            throw GeneratorError.emptyContent
        }

        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8) else {
            throw GeneratorError.invalidJSON
        }

        let decoder = PackJSONDecoderFactory.decoder()
        do {
            return try decoder.decode(PackJsonDTO.self, from: jsonData)
        } catch {
            throw GeneratorError.decoding(error.localizedDescription)
        }
    }
}

extension OpenAIPackGenerator {
    /// OpenAI API連携で想定されるエラー
    enum GeneratorError: LocalizedError {
        /// HTTPレスポンスが取得できない、あるいは不正な場合
        case invalidResponse
        /// レスポンス本文に含まれるエラー
        case server(message: String)
        /// choicesが空でJSONが取り出せない場合
        case emptyContent
        /// JSONの文字列化に失敗した場合
        case invalidJSON
        /// JSON -> DTOデコード時の失敗
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "OpenAI APIの応答が不正です。ネットワーク状況を確認してください。"
            case .server(let message):
                return message
            case .emptyContent:
                return "OpenAI APIから有効なJSONが返ってきませんでした。"
            case .invalidJSON:
                return "OpenAI APIの応答をJSONとして解釈できませんでした。"
            case .decoding(let detail):
                return "JSON解析に失敗しました: \(detail)"
            }
        }
    }
}

private extension OpenAIPackGenerator {
    /// ChatCompletionエンドポイントへ送信するリクエストボディ
    struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let responseFormat: ResponseFormat

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case responseFormat = "response_format"
        }
    }

    /// ChatCompletionのメッセージ
    struct Message: Encodable {
        let role: String
        let content: String
    }

    /// レスポンス形式。`json_object`を指定して確実にJSONだけを取得。
    struct ResponseFormat: Encodable {
        let type: String

        static let jsonObject = ResponseFormat(type: "json_object")
    }

    /// OpenAI APIの成功レスポンス
    struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let role: String
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    /// OpenAI APIが返すエラー構造
    struct OpenAIAPIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String
        }
        let error: APIError
    }
}
