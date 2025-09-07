import Foundation
import CryptoKit

/// Generates a short, hashed UUID string.
/// - Parameter length: Maximum length of the resulting identifier.
/// - Returns: A base64-encoded hash truncated to the given length.
func hashedShortUUID(length: Int = 10) -> String {
    let uuid = UUID().uuidString
    let hash = SHA256.hash(data: uuid.data(using: .utf8)!)
    return Data(hash).base64EncodedString().prefix(length).description
}

