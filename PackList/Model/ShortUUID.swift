//
//  ShortUUID.swift
//  PackList
//
//  Pack / Group / Item の `@Attribute(.unique) var id: String` に格納する短い ID を生成する。
//
//  ─── 長さの決定根拠 ────────────────────────────────────────────────────────
//  旧バージョンの既定値は 16 文字だった。
//   - 文字種：URL-safe base64（64 種類）
//   - キースペース：64^16 = 2^96 ≒ 7.9 × 10^28
//   - 誕生日パラドックスによる 50% 衝突件数：約 2^48 件 (≒ 281 兆)
//
//  実運用ではユーザー 1 人あたりせいぜい数千件なので 16 文字でも十分だが、
//  以下の要因で衝突確率を厳しめに見積もる必要が出てきた：
//   - バックアップを別端末で復元して統合するケース
//   - 共有された .packlin を多人数で取り込むケース
//   - 将来的にクラウド同期や複数アカウントを跨いだ共有を行う可能性
//
//  そのため既定値を 22 文字へ拡張した。
//   - キースペース：64^22 = 2^132 ≒ 5.4 × 10^39
//   - 誕生日パラドックスによる 50% 衝突件数：約 2^66 件 (≒ 7.4 × 10^19)
//   - これは実用上「事実上の一意性が保たれる」と言える水準
//
//  ─── 既存データとの互換性 ───────────────────────────────────────────────
//  `@Attribute(.unique)` の制約は「値が一意であること」だけで長さ条件はない。
//  そのため旧端末で生成された 16 文字 ID と新規生成される 22 文字 ID は
//  同じデータベース内で共存できる。マイグレーションは不要。
//

import Foundation
import CryptoKit

/// 短い一意 ID を生成する
/// - Parameter length: 出力文字数。既定値 22 で実用上の一意性を担保する。
///                     旧データ互換のため 16 でも呼べる（テスト用途想定）。
/// - Returns: URL-safe base64 にエンコードしたハッシュ値を `length` 文字で切り出した文字列
func shortUUID(length: Int = 22) -> String {
    // UUID().uuidString は "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX" の ASCII 36 文字。
    // CryptoKit の SHA256 へ食わせるためにバイト列へ変換する。
    let uuid = UUID().uuidString
    guard let data = uuid.data(using: .utf8) else {
        // UUID().uuidString は仕様上 ASCII のみなので utf8 変換は常に成功する。
        // ただし `!` で潰すよりは、万一の OS バグ等に備えてフォールバックを返す方が安全。
        // フォールバックではハイフンを除いた UUID 文字列の先頭を切り出して返す。
        return String(uuid.replacingOccurrences(of: "-", with: "").prefix(length))
    }
    // SHA256 でハッシュ化（32 バイト = 256 ビット）。UUID をハッシュする理由は、
    // UUID v4 のランダム部分が偏っても base64 表現が均一に分布するようにするため。
    let hash = SHA256.hash(data: data)
    // base64 へエンコード（44 文字）。base64 は '+' '/' '=' を含むため URL/ファイル名で扱いにくい。
    let base64 = Data(hash).base64EncodedString()
    // URL-safe base64 へ変換する RFC 4648 §5 の手順。
    //   '+' → '-'
    //   '/' → '_'
    //   '=' （パディング）→ 除去
    let urlSafe = base64
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    // 先頭 `length` 文字を切り出して短縮 ID として返す。
    // SHA256 出力は均一分布なので、先頭を切っても残った部分の分布は崩れない。
    return String(urlSafe.prefix(length))
}

