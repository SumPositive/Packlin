//
//  String.swift
//  PackList
//
//  Created by Sum Positive on 2025/09/16.
//

import Foundation


extension String {
    
    /// 末尾の「空白・改行」を削除
    var trimTrailSpacesAndNewlines: String {
        replacingOccurrences(
            of: "\\s+$",  // #"([\s\u{00A0}\u{3000}])+$"#,
            with: "",
            options: .regularExpression
        )
    }
    
}
