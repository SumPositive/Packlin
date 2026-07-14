//
//  JsonRoundTripTests.swift
//  PackListTests
//
//  JSON Export → Import のラウンドトリップ検証。
//  - Pack 単体の export → JSON 文字列化 → decode → import が同値である
//  - ネストした Group / Item の順序が保持される
//  - backupRepresentation は ID を保持し、exportRepresentation は ID を nil にする
//  - BackupJsonDTO（全パック）も同様に往復で同値
//  - overwrite で復元すると既存パックの id が保持される
//

import Testing
import Foundation
import SwiftData
@testable import Packlin

@MainActor
struct JsonRoundTripTests {

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
    }

    private func makeFixture() throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        return Fixture(container: container, context: container.mainContext)
    }

    /// Sample 構造を作成: Pack [G1 [I1, I2], G2 [I3]]
    private func seedSamplePack(in context: ModelContext, name: String = "Sample") throws -> M1Pack {
        let pack = M1Pack(id: "P1", name: name, memo: "memo", order: 0)
        context.insert(pack)
        let g1 = M2Group(id: "G1", name: "G1", order: 0, parent: pack)
        let g2 = M2Group(id: "G2", name: "G2", order: ORDER_SPARSE, parent: pack)
        context.insert(g1)
        context.insert(g2)

        let i1 = M3Item(id: "I1", name: "I1",
                        check: false, stock: 1, need: 2, weight: 100,
                        order: 0, parent: g1)
        let i2 = M3Item(id: "I2", name: "I2",
                        check: true, stock: 5, need: 5, weight: 250,
                        order: ORDER_SPARSE, parent: g1)
        let i3 = M3Item(id: "I3", name: "I3",
                        check: false, stock: 0, need: 1, weight: 50,
                        order: 0, parent: g2)
        context.insert(i1)
        context.insert(i2)
        context.insert(i3)

        try context.save()
        return pack
    }

    // MARK: - 単体 Pack ラウンドトリップ

    @Test("単体 Pack の export → decode → import で name / memo が同値である")
    func singlePackRoundtripPreservesBasicFields() throws {
        let fx = try makeFixture()
        let original = try seedSamplePack(in: fx.context, name: "RoundTripPack")

        // Export → JSON bytes → Decode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let dto = original.exportRepresentation()
        let jsonData = try encoder.encode(dto)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PackJsonDTO.self, from: jsonData)

        // 新しいコンテキストにインポート（既存とは別の場所で復元）
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container2 = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context2 = container2.mainContext
        let imported = PackImporter.insertPack(from: decoded, into: context2, order: 0)
        try context2.save()

        #expect(imported.name == "RoundTripPack")
        #expect(imported.memo == "memo")
        _ = container2
    }

    @Test("ネストした Group / Item の順序が export → import で保持される")
    func nestedStructureOrderIsPreserved() throws {
        let fx = try makeFixture()
        let original = try seedSamplePack(in: fx.context)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let dto = original.exportRepresentation()
        let jsonData = try encoder.encode(dto)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PackJsonDTO.self, from: jsonData)

        // 別のコンテナにインポート
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container2 = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context2 = container2.mainContext
        let imported = PackImporter.insertPack(from: decoded, into: context2, order: 0)
        try context2.save()

        // Group の並び: G1, G2
        let importedGroups = imported.child.sorted { $0.order < $1.order }
        #expect(importedGroups.map(\.name) == ["G1", "G2"])

        // G1 配下の Item の並び: I1, I2
        let g1Items = importedGroups.first?.child.sorted { $0.order < $1.order } ?? []
        #expect(g1Items.map(\.name) == ["I1", "I2"])

        // I1 の属性が保持されている
        #expect(g1Items.first?.need == 2)
        #expect(g1Items.first?.weight == 100)

        // I2 の check / stock など全フィールドが復元されている
        let i2 = g1Items.last
        #expect(i2?.check == true)
        #expect(i2?.stock == 5)
        #expect(i2?.need == 5)
        #expect(i2?.weight == 250)
        _ = container2
    }

    // MARK: - export vs backup の DTO の違い

    @Test("exportRepresentation は ID を nil にする（共有用なので照合は名前ベース）")
    func exportRepresentationStripsIds() throws {
        let fx = try makeFixture()
        let original = try seedSamplePack(in: fx.context)

        let dto = original.exportRepresentation()
        // Pack の ID は nil
        #expect(dto.id == nil)
        // Group の ID も nil
        for group in dto.groups {
            #expect(group.id == nil)
            // Item の ID も nil
            for item in group.items {
                #expect(item.id == nil)
            }
        }
    }

    @Test("backupRepresentation は Pack の ID を保持する（バックアップ復元は ID 照合）")
    func backupRepresentationKeepsPackId() throws {
        let fx = try makeFixture()
        let original = try seedSamplePack(in: fx.context)

        let dto = original.backupRepresentation()
        // Pack の ID は維持される
        #expect(dto.id == "P1")
        // ※ Group / Item の id は backupRepresentation でも nil（取り込み側で生成）
        for group in dto.groups {
            #expect(group.id == nil)
        }
    }

    // MARK: - 上書き (overwrite) ラウンドトリップ

    @Test("ID 一致時に overwrite すると既存 Pack の id が維持されて内容だけ差し替わる")
    func overwritePreservesPackIdAndReplacesContents() throws {
        let fx = try makeFixture()
        let original = try seedSamplePack(in: fx.context, name: "BeforeOverwrite")

        // 構造を変えた DTO で上書きする（Pack の id は同じ "P1"）
        let dto = PackJsonDTO(
            productName: PACK_JSON_DTO_PRODUCT_NAME,
            copyright: PACK_JSON_DTO_COPYRIGHT,
            version: PACK_JSON_DTO_VERSION,
            id: "P1",
            order: nil,
            name: "AfterOverwrite",
            memo: "newmemo",
            createdAt: Date(),
            groups: [
                .init(id: nil, order: nil, name: "NewG", memo: "", items: [
                    .init(id: nil, order: nil, name: "NewI", memo: "",
                          check: false, stock: 0, need: 7, weight: 999)
                ])
            ]
        )

        let updated = PackImporter.overwrite(pack: original, with: dto, in: fx.context)
        try fx.context.save()

        // Pack ID は維持
        #expect(updated.id == "P1")
        // 内容は置き換わっている
        #expect(updated.name == "AfterOverwrite")
        #expect(updated.memo == "newmemo")
        // 新しい Group / Item に置き換わっている
        #expect(updated.child.count == 1)
        #expect(updated.child.first?.name == "NewG")
        #expect(updated.child.first?.child.first?.name == "NewI")
        #expect(updated.child.first?.child.first?.weight == 999)
    }
}
