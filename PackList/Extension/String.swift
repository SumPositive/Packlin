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
        return components(separatedBy: "\n")
            .prefix(maxLines)
            .joined(separator: "  ")
    }

}
