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

/// チャッピーが返すパックの部分変更
struct PackChangeDTO: Codable {
    enum Action: String, Codable {
        case createPack = "create_pack"
        case updatePack = "update_pack"
        case addGroup = "add_group"
        case updateGroup = "update_group"
        case deleteGroup = "delete_group"
        case moveGroup = "move_group"
        case addItem = "add_item"
        case updateItem = "update_item"
        case deleteItem = "delete_item"
        case moveItem = "move_item"
    }

    enum Placement: String, Codable {
        case head
        case tail
        case after
    }

    let action: Action
    let targetId: String?
    let parentId: String?
    let referenceId: String?
    let placement: Placement?
    let afterId: String?
    let name: String?
    let memo: String?
    let check: Bool?
    let stock: Int?
    let need: Int?
    let weight: Int?
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

    /// AI差分が現在要素を特定できるよう内部IDを保持して書き出す
    func conversationRepresentation() -> PackJsonDTO {
        PackJsonDTO(
            productName: PACK_JSON_DTO_PRODUCT_NAME,
            copyright: PACK_JSON_DTO_COPYRIGHT,
            version: PACK_JSON_DTO_VERSION,
            id: id,
            order: order,
            name: name,
            memo: memo,
            createdAt: createdAt,
            groups: child
                .sorted { $0.order < $1.order }
                .map { $0.conversationRepresentation() }
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

    /// AI差分向けにグループとアイテムのIDを保持する
    func conversationRepresentation() -> PackJsonDTO.Group {
        PackJsonDTO.Group(
            id: id,
            order: order,
            name: name,
            memo: memo,
            items: child
                .sorted { $0.order < $1.order }
                .map { $0.conversationRepresentation() }
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

    /// AI差分向けにアイテムIDを保持する
    func conversationRepresentation() -> PackJsonDTO.Group.Item {
        PackJsonDTO.Group.Item(
            id: id,
            order: order,
            name: name,
            memo: memo,
            check: check,
            stock: stock,
            need: need,
            weight: weight
        )
    }
}
