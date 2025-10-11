//
//  PackJSONDecoder.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import Foundation

/// PackList専用のJSONデコーダーをまとめたヘルパー
/// - ChatGPT/OpenAI APIから返ってくるJSONを安全に解釈できるよう、
///   `createdAt` フィールドはISO8601文字列のみを受け入れる。
enum PackJSONDecoderFactory {
    /// PackListが期待する形式を読み取れる`JSONDecoder`を生成
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { codingPath -> Date in
            let container = try codingPath.singleValueContainer()

            // JSON内のcreatedAtはISO8601の文字列だけをサポートする方針に統一
            // そのため、まず文字列としてデコードし、ISO8601DateFormatterで解析する
            let isoString = try container.decode(String.self)

            // ミリ秒有りの形式（withFractionalSeconds）を優先的に解析
            if let isoDate = ISO8601DateFormatter.packFractionalFormatter.date(from: isoString) {
                return isoDate
            }

            // 秒以下が無い一般的なISO8601形式もサポート
            if let fallbackDate = ISO8601DateFormatter.packPlainFormatter.date(from: isoString) {
                return fallbackDate
            }

            // ここまで到達した場合はISO8601として解釈できなかったためエラーにする
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "createdAtはISO8601形式の文字列で指定してください。"
            )
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    /// `createdAt`の解析で利用するISO8601フォーマッタ（ミリ秒あり）
    static let packFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `createdAt`の解析で利用するISO8601フォーマッタ（ミリ秒なし）
    static let packPlainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
