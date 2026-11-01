//
//  GenerationRequestIdStore.swift
//  PackList
//
//  Created by sumpo on 2026/11/01.
//

import Foundation
import CryptoKit

/// AI生成の依頼IDを控え、同じ依頼の再試行で同じIDを送るためのヘルパ
/// 生成後に通信が切れて応答を受け取れなくても、同じIDで送り直せばサーバーは消費せずに保存済みの結果を返す
/// - 依頼の中身（要望・お試しかどうか・元のパック）が同じなら同じIDを使い、変わったら新しいIDにする
/// - 生成結果を受け取れたら消す（次の依頼は新しいIDにする）
/// - アプリを終了しても再試行できるよう UserDefaults に保存する
enum GenerationRequestIdStore {
    private static let storageKey = "azuki.ai.pendingGenerationRequest"
    /// 使い回す期間。サーバーの保存期間（7日）より短くする
    private static let lifetime: TimeInterval = 24 * 60 * 60

    private struct Pending: Codable {
        let requestId: String
        let fingerprint: String
        let createdAt: Date
    }

    /// 依頼の中身に対応する依頼IDを返す（控えと同じ中身なら控えのID、違えば新しく作って控える）
    static func requestId(requirement: String, isTrial: Bool, basePack: PackJsonDTO?) -> String {
        let fingerprint = makeFingerprint(requirement: requirement, isTrial: isTrial, basePack: basePack)
        if let pending = load(),
           pending.fingerprint == fingerprint,
           Date().timeIntervalSince(pending.createdAt) < lifetime {
            return pending.requestId
        }
        let created = Pending(requestId: UUID().uuidString.lowercased(), fingerprint: fingerprint, createdAt: Date())
        if let data = try? JSONEncoder().encode(created) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        return created.requestId
    }

    /// 生成結果を受け取れたので控えを消す
    static func clear(requestId: String) {
        guard load()?.requestId == requestId else { return }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func load() -> Pending? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Pending.self, from: data)
    }

    /// 依頼の中身を要約した値（中身が同じかどうかの判定だけに使い、送信はしない）
    private static func makeFingerprint(requirement: String, isTrial: Bool, basePack: PackJsonDTO?) -> String {
        var source = "\(isTrial)|\(requirement)"
        if let basePack {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            if let data = try? encoder.encode(basePack), let json = String(data: data, encoding: .utf8) {
                source += "|\(json)"
            }
        }
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
