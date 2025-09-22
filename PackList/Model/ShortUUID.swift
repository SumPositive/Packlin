//
//  ShortUUID.swift
//  PackList
//　　　 UUID（32Byte）では長すぎるので、本件では12Byteで十分と判断した
//
//  Created by sumpo on 2025/09/07.
//

import Foundation
import CryptoKit

/// Generates a short, hashed UUID string.
/// - Parameter length: Maximum length of the resulting identifier.
/// - Returns: URL Safe base64-encoded hash truncated to the given length.
func shortUUID(length: Int = 16) -> String {
    let uuid = UUID().uuidString
    let hash = SHA256.hash(data: uuid.data(using: .utf8)!)
    let base64 = Data(hash).base64EncodedString()
    let urlSafe = base64        // URLセーフにするための置換
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return String(urlSafe.prefix(length))
}

