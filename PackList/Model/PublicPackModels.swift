import Foundation

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
