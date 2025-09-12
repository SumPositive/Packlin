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
/// - Returns: A base64-encoded hash truncated to the given length.
func shortUUID(length: Int = 12) -> String {
    let uuid = UUID().uuidString
    let hash = SHA256.hash(data: uuid.data(using: .utf8)!)
    return Data(hash).base64EncodedString().prefix(length).description
}

