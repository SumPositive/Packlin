//
//  KeychainStorage.swift
//  PackList
//
//  Created by OpenAI on 2024/05/23.
//

import Foundation
import Security

/// Keychainをラップして文字列や数値を安全に保存・取得するためのユーティリティ
/// アプリ削除後も値が保持されることを期待してクレジット残高やユーザーIDの保存に利用する
struct KeychainStorage {
    /// Keychainに保存する際のサービス名。Bundle IDがあればそれを、無ければ固定文字列を使用する
    private let service: String
    /// true なら iCloud キーチェーンで同じ Apple ID の端末へ同期する項目として扱う
    /// 同期しない項目とは別の項目になる（同じキーでも互いに読み書きしない）
    private let synchronizable: Bool

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier, synchronizable: Bool = false) {
        self.synchronizable = synchronizable
        if let identifier = bundleIdentifier, identifier.isEmpty == false {
            self.service = identifier
        } else {
            // Previewや単体テストでも安定したキーになるように固定値を採用
            self.service = "com.azukid.sumpo.packlist"
        }
    }

    /// 指定したキーへ文字列を保存する
    /// - Parameters:
    ///   - value: 保存したい文字列
    ///   - key: 値を紐づけるためのキー
    /// - Returns: 保存できたら true（失敗を確かめたい呼び出し元のため）
    @discardableResult
    func saveString(_ value: String, forKey key: String) -> Bool {
        // 既存エントリの有無に関係なく確実に更新できるよう削除→追加の順で処理する
        deleteItem(forKey: key)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8)
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
            // 同期する項目は「この端末のみ」の属性を使えないため、初回ロック解除後に読める設定にする
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            log(.error, "SecItemAdd failed: key=\(key) status=\(status)")
            return false
        }
        return true
    }

    /// 指定したキーから文字列を読み出す
    /// - Parameter key: 取得したい値のキー
    /// - Returns: 保存済みであればその文字列、存在しなければnil
    func loadString(forKey key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }

    /// 指定したキーへ整数を保存する（内部では文字列へ変換して保存）
    /// - Parameters:
    ///   - value: 保存したい整数値
    ///   - key: 値を紐づけるためのキー
    func saveInt(_ value: Int, forKey key: String) {
        saveString(String(value), forKey: key)
    }

    /// 指定したキーから整数を取得する
    /// - Parameter key: 取得したい値のキー
    /// - Returns: 保存済みであれば整数値、存在しない場合はnil
    func loadInt(forKey key: String) -> Int? {
        if let stringValue = loadString(forKey: key),
           let intValue = Int(stringValue) {
            return intValue
        }
        return nil
    }

    /// 指定したキーの値を削除する
    /// - Parameter key: 削除対象のキー
    func deleteItem(forKey key: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log(.error, "SecItemDelete failed: key=\(key) status=\(status)")
        }
    }
}
