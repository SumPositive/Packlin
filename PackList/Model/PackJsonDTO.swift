//
//  PackJsonDTO.swift
//  PackList
//
//  Created by sumpo on 2025/09/23.
//

import Foundation

/// 全パックをまとめたバックアップ用DTO
struct BackupJsonDTO: Codable {
    let productName: String
    let copyright: String
    let version: String
    let exportedAt: Date
    let packs: [PackJsonDTO]

    enum CodingKeys: String, CodingKey {
        case productName = "ProductName"
        case copyright
        case version
        case exportedAt
        case packs
    }
}

struct PackJsonDTO: Codable {
    /// グループやアイテム構造を内包するDTO
    struct Group: Codable {
        struct Item: Codable {
            /// JSONには含めないが、従来形式との互換性維持のために残しておく
            let id: M3Item.ID?
            /// 並び順はインポート時に採番するためオプショナルに変更
            let order: Int?
            let name: String
            let memo: String
            let check: Bool
            /// stockもアプリ内で決定するので任意扱い
            let stock: Int?
            let need: Int
            let weight: Int
        }

        let id: M2Group.ID?
        let order: Int?
        let name: String
        let memo: String
        let items: [Item]
    }

    /// 生成元アプリを識別するための名称（JSONではProductNameキー）
    let productName: String
    let copyright: String
    let version: String
    let id: M1Pack.ID?
    let order: Int?
    let name: String
    let memo: String
    let createdAt: Date
    let groups: [Group]

    /// ChatGPTへ指示するキー名に合わせてプロパティをマッピング
    enum CodingKeys: String, CodingKey {
        case productName = "ProductName"
        case copyright
        case version
        case id
        case order
        case name
        case memo
        case createdAt
        case groups
    }
}

extension M1Pack {
    func exportRepresentation() -> PackJsonDTO {
        PackJsonDTO(
            productName: PACK_JSON_DTO_PRODUCT_NAME, // 共有時にアプリ名を残す
            copyright: PACK_JSON_DTO_COPYRIGHT, // Load時に差異チェック
            version: PACK_JSON_DTO_VERSION, // Load時に差異チェックしてマイグレション
            id: nil, // 読み込み側で生成
            order: nil, // 読み込み側で決定
            name: name,
            memo: memo,
            createdAt: createdAt,
            groups: child
                .sorted { $0.order < $1.order }
                .map { $0.exportRepresentation() }
        )
    }

    /// バックアップ用。IDを含めてエクスポートすることで、インポート時にIDで同一パックを照合できる
    func backupRepresentation() -> PackJsonDTO {
        PackJsonDTO(
            productName: PACK_JSON_DTO_PRODUCT_NAME,
            copyright: PACK_JSON_DTO_COPYRIGHT,
            version: PACK_JSON_DTO_VERSION,
            id: id, // バックアップではIDを保持してインポート側の重複判定に使う
            order: nil,
            name: name,
            memo: memo,
            createdAt: createdAt,
            groups: child
                .sorted { $0.order < $1.order }
                .map { $0.exportRepresentation() }
        )
    }
}

extension M2Group {
    func exportRepresentation() -> PackJsonDTO.Group {
        PackJsonDTO.Group(
            id: nil, // グループIDも読み込み側で生成
            order: nil,
            name: name,
            memo: memo,
            items: child
                .sorted { $0.order < $1.order }
                .map { $0.exportRepresentation() }
        )
    }
}

extension M3Item {
    func exportRepresentation() -> PackJsonDTO.Group.Item {
        PackJsonDTO.Group.Item(
            id: nil, // 読み込み側で生成
            order: nil,
            name: name,
            memo: memo,
            check: check,
            stock: stock,
            need: need,
            weight: weight
        )
    }
}
