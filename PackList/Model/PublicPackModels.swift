import Foundation

// 公式作者名と誤認される固定のニックネームを端末側で軽く拒否する
func isUnavailableAuthorNickname(_ nickname: String) -> Bool {
    let normalized = nickname
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
    return normalized.hasPrefix("sumpo")
}

/// 公開パック一覧・検索の1件（他ユーザー向け。作者ニックネームを含む）
/// createdAt/updatedAt はUI表示に使わないため、デコード対象から外して日付フォーマット差異を避ける
struct PublicPackSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let memo: String
    let locale: String?
    let groupCount: Int
    let itemCount: Int
    let totalWeight: Int
    let downloadCount: Int
    /// 作者ニックネーム。サーバー側で未設定なら「匿名」が入る
    let author: String
    /// 閲覧者自身が公開したパックなら true（削除ボタンを出す）
    let isMine: Bool
    /// 公開日時（エポックミリ秒）。端末側でローカル時刻・分まで整形する
    let publishedAtMs: Double?

    /// 公開日時の Date 表現
    var publishedAt: Date? {
        guard let publishedAtMs else { return nil }
        return Date(timeIntervalSince1970: publishedAtMs / 1000)
    }
}

/// 自分の公開済みパック1件（公開管理画面用。status と sourcePackId を含む）
struct OwnPublishedSummary: Decodable, Identifiable {
    let id: String
    let sourcePackId: String
    let name: String
    let memo: String
    let locale: String?
    let groupCount: Int
    let itemCount: Int
    let totalWeight: Int
    let downloadCount: Int
    let status: String
}
