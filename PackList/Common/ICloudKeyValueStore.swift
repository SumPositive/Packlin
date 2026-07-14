//
//  ICloudKeyValueStore.swift
//  PackList
//
//  iCloud Key-Value Store (NSUbiquitousKeyValueStore) をラップするユーティリティ。
//  端末が壊れても同じ Apple ID の新端末で userId を復元できるようにするために使う。
//  entitlement `com.apple.developer.ubiquity-kvstore-identifier` が必要。
//
//  ※ iCloud KVS は「同じ Apple ID を使い、iCloud Drive/Key-Value が有効」な場合のみ同期する。
//    サインアウトや iCloud 無効の端末では nil を返すだけで、アプリ動作は妨げない設計にする。
//

import Foundation

/// iCloud Key-Value Store の薄いラッパー。取得・保存・同期のみを提供する。
struct ICloudKeyValueStore {
    private let store: NSUbiquitousKeyValueStore

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    /// 文字列を取得する。未設定や空文字なら nil。
    func loadString(forKey key: String) -> String? {
        // 最新のクラウド値を反映してから読む（初回起動直後の取りこぼしを減らす）
        store.synchronize()
        guard let value = store.string(forKey: key), value.isEmpty == false else {
            return nil
        }
        return value
    }

    /// 文字列を保存し、クラウドへの反映を促す。
    /// 同期は非同期・ベストエフォートで、失敗してもアプリ動作は続行する。
    func saveString(_ value: String, forKey key: String) {
        store.set(value, forKey: key)
        store.synchronize()
    }

    /// 指定キーを削除する（DEBUG のリセット用など）。
    func removeValue(forKey key: String) {
        store.removeObject(forKey: key)
        store.synchronize()
    }
}
