//
//  InfoPlistSecrets.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import Foundation

/// Info.plistから安全に扱えない機密値（APIキーなど）を読み出すためのヘルパー
/// - Info.plistはアプリバンドルへ平文で埋め込まれるため、秘匿性は期待できない点に注意
struct InfoPlistSecrets {
    /// シングルトン的に再利用して余計なディクショナリ読み出しを避ける
    static let shared = InfoPlistSecrets()

    /// Info.plist内に定義されたOpenAI APIキー
    /// - 実運用での埋め込みは推奨されない（容易に抽出される）ため、開発中の仮キーや自動テスト用途に限定する想定
    let bundledOpenAIAPIKey: String?

    /// 指定バンドルから値を読み出す
    /// - Parameter bundle: 既定ではメインバンドル
    init(bundle: Bundle = .main) {
        // Info.plistからキーを取り出し、文字列でない場合は破棄
        if let rawValue = bundle.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String {
            // 前後空白を除去し、空文字列ならnilへ変換して扱いやすくする
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.bundledOpenAIAPIKey = trimmed.isEmpty ? nil : trimmed
        } else {
            self.bundledOpenAIAPIKey = nil
        }
    }
}
