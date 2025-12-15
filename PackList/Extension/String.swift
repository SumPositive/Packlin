//
//  String.swift
//  PackList
//
//  Created by sumpo on 2025/09/16.
//

import Foundation
import SwiftUI


extension String {

    /// 末尾切り捨て
    func truncTail(_ len: Int) -> String {
        if self.isEmpty || len <= 0 || self.count <= len {
            return self
        }
        return String(self.prefix(len - 1)) + "…"
    }

    /// 末尾の「空白・改行」を削除
    var trimTrailSpacesAndNewlines: String {
        replacingOccurrences(
            of: "\\s+$",  // #"([\s\u{00A0}\u{3000}])+$"#,
            with: "",
            options: .regularExpression
        )
    }

    /// 空文字列の場合にローカライズ済みのプレースホルダを返す
    /// - Parameter placeholderKey: 置き換えに使用する `LocalizedStringKey`
    /// - Returns: 空文字列ならローカライズキー、そうでなければ元の文字列を `Text` として返す
    func placeholderText(_ placeholderKey: LocalizedStringKey) -> Text {
        isEmpty ? Text(placeholderKey) : Text(verbatim: self)
    }

    /// 空文字列の場合にローカライズ済みのプレースホルダを返す
    /// - Parameter placeholder: 置き換えに使用する `LocalizedStringResource`
    /// - Returns: 空文字列ならローカライズ文字列、そうでなければ元の文字列を `String` として返す
    func placeholder(_ placeholder: LocalizedStringResource) -> String {
        isEmpty ? String(localized: placeholder) : self
    }

    /// 指定行数までで文字列を切り、末尾の改行を取り除く
    /// - Parameter maxLines: 上限とする行数（0以下なら空文字を返す）
    /// - Returns: スペース区切りで上限行までを残した文字列
    func limitedByNewlines(maxLines: Int) -> String {
        if maxLines <= 0 { return "" }

        // 改行単位で区切り、指定行数分だけを順に拾っていく
        var collected: [Substring] = []
        var searchStart = startIndex

        while searchStart < endIndex && collected.count < maxLines {
            // 次の改行位置を探し、見つかればそこまでを1行として扱う
            if let newlineIndex = self[searchStart...].firstIndex(of: "\n") {
                collected.append(self[searchStart..<newlineIndex])
                // 次の検索開始位置は改行の直後
                searchStart = index(after: newlineIndex)
            } else {
                // 残りに改行が無ければ末尾までを丸ごと1行として追加する
                collected.append(self[searchStart..<endIndex])
                // 末尾まで到達したのでループを抜ける
                break
            }
        }
        // 取得した行をスペース"  "で再結合し、末尾の改行は含めない
        return collected.joined(separator: "  ") //\n")
    }

}
