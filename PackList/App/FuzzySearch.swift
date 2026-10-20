//
//  FuzzySearch.swift
//  PackList
//
//  タグやアイテムの検索で使う曖昧一致
//  大文字小文字・全角半角・ひらがなカタカナ・濁点半濁点やアクセントの違いを区別しない
//

import Foundation

extension String {
    /// 曖昧一致用に揃えた文字列
    var fuzzySearchKey: String {
        // 先に全角半角を揃え（半角カナ→全角カナ）、ひらがなをカタカナにそろえてから、大文字小文字・濁点・アクセントを外す
        let width = folding(options: .widthInsensitive, locale: nil)
        let kana = width.applyingTransform(.hiraganaToKatakana, reverse: false) ?? width
        let folded = kana.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        // かなの濁点・半濁点は上の処理で外れないので、分解して取り除く（パ→ハ、ガ→カ）
        let scalars = folded.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !Self.kanaVoicedMarks.contains($0) }
        return String(String.UnicodeScalarView(scalars)).precomposedStringWithCanonicalMapping
    }

    /// 結合用の濁点・半濁点
    private static let kanaVoicedMarks: Set<Unicode.Scalar> = ["\u{3099}", "\u{309A}"]

    /// keyword を曖昧一致で含むか（keyword が空なら true）
    func fuzzyContains(_ keyword: String) -> Bool {
        let key = keyword.fuzzySearchKey
        guard !key.isEmpty else { return true }
        return fuzzySearchKey.contains(key)
    }
}
