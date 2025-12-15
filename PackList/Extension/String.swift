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
    /// - Returns: 改行区切りで上限行までを残した文字列
    func limitedByNewlines(maxLines: Int) -> String {
        if maxLines <= 0 { return "" }
        // 改行を数えながら走査し、上限行を越える手前で切り取る
        var remainingLines = maxLines
        var currentIndex = startIndex
        while currentIndex < endIndex {
            let character = self[currentIndex]
            if character == "\n" {
                remainingLines -= 1
                if remainingLines <= 0 { break }
            }
            currentIndex = index(after: currentIndex)
        }
        // 走査位置までを取得し、末尾の改行だけを削除する
        var result = String(self[..<currentIndex])
        while result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }

}
