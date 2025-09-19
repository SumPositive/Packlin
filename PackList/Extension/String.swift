//
//  String.swift
//  PackList
//
//  Created by Sum Positive on 2025/09/16.
//

import Foundation
import SwiftUI


extension String {

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

}
