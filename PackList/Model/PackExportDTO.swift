import Foundation

struct PackExportDTO: Codable {
    struct Group: Codable {
        struct Item: Codable {
            let id: M3Item.ID
            let order: Int
            let name: String
            let memo: String
            let check: Bool
            let stock: Int
            let need: Int
            let weight: Int
        }

        let id: M2Group.ID
        let order: Int
        let name: String
        let memo: String
        let items: [Item]
    }

    let copyright: String
    let version: String
    let id: M1Pack.ID
    let order: Int
    let name: String
    let memo: String
    let createdAt: Date
    let groups: [Group]
}

extension M1Pack {
    func exportRepresentation() -> PackExportDTO {
        PackExportDTO(
            copyright: "2025 sumpo/azukid",
            version: "3.0",
            id: id,
            order: order,
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
    func exportRepresentation() -> PackExportDTO.Group {
        PackExportDTO.Group(
            id: id,
            order: order,
            name: name,
            memo: memo,
            items: child
                .sorted { $0.order < $1.order }
                .map { $0.exportRepresentation() }
        )
    }
}

extension M3Item {
    func exportRepresentation() -> PackExportDTO.Group.Item {
        PackExportDTO.Group.Item(
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
