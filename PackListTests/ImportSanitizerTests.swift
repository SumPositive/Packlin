//
//  ImportSanitizerTests.swift
//  PackListTests
//
//  Fix 5（PackImporter のサニタイズ層）の動作検証。
//  Sanitizer は private なので、公開 API である PackImporter.insertPack を通じて
//  「壊れた DTO を流し込んだら正しくクランプされたモデルが保存される」ことを確認する。
//

import Testing
import Foundation
import SwiftData
@testable import Packlin

@MainActor
struct ImportSanitizerTests {

    // MARK: - Fixture

    /// container を強参照で保持するための構造体。
    /// ローカル変数で ModelContainer を作って context.mainContext だけ返すと
    /// container がスコープ外で解放され、SwiftData の insert/fetch が trap する。
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

    /// テスト用に最小限のフィールドを持つ DTO を作る
    private func makePackDTO(
        name: String = "Pack",
        memo: String = "",
        createdAt: Date = Date(),
        groups: [PackJsonDTO.Group] = []
    ) -> PackJsonDTO {
        PackJsonDTO(
            productName: PACK_JSON_DTO_PRODUCT_NAME,
            copyright: PACK_JSON_DTO_COPYRIGHT,
            version: PACK_JSON_DTO_VERSION,
            id: nil,
            order: nil,
            name: name,
            memo: memo,
            createdAt: createdAt,
            groups: groups
        )
    }

    private func makeItemDTO(
        name: String = "Item",
        memo: String = "",
        check: Bool = false,
        stock: Int? = 0,
        need: Int = 1,
        weight: Int = 0
    ) -> PackJsonDTO.Group.Item {
        .init(id: nil, order: nil, name: name, memo: memo,
              check: check, stock: stock, need: need, weight: weight)
    }

    private func makeGroupDTO(
        name: String = "Group",
        items: [PackJsonDTO.Group.Item] = []
    ) -> PackJsonDTO.Group {
        .init(id: nil, order: nil, name: name, memo: "", items: items)
    }

    // MARK: - 文字列長クランプ

    @Test("200文字を超える Pack.name は APP_MAX_NAME_LEN に切り詰められる")
    func packNameIsTruncatedToMaxLength() throws {
        let fx = try makeFixture()
        let longName = String(repeating: "あ", count: 500) // 500文字
        let dto = makePackDTO(name: longName)

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        #expect(pack.name.count == APP_MAX_NAME_LEN)
    }

    @Test("200文字を超える Pack.memo は APP_MAX_MEMO_LEN に切り詰められる")
    func packMemoIsTruncatedToMaxLength() throws {
        let fx = try makeFixture()
        let longMemo = String(repeating: "x", count: 1000)
        let dto = makePackDTO(memo: longMemo)

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        #expect(pack.memo.count == APP_MAX_MEMO_LEN)
    }

    @Test("200文字以内の Pack.name はそのまま保持される")
    func shortPackNameIsPreserved() throws {
        let fx = try makeFixture()
        let name = "通常のパック名"
        let dto = makePackDTO(name: name)

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        #expect(pack.name == name)
    }

    // MARK: - 数値クランプ

    @Test("負の weight は 0 にクランプされる")
    func negativeWeightIsClampedToZero() throws {
        let fx = try makeFixture()
        let item = makeItemDTO(weight: -100)
        let group = makeGroupDTO(items: [item])
        let dto = makePackDTO(groups: [group])

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        let importedItem = pack.child.first?.child.first
        #expect(importedItem?.weight == 0)
    }

    @Test("APP_MAX_WEIGHT_NUM を超える weight は上限にクランプされる")
    func excessiveWeightIsClampedToMax() throws {
        let fx = try makeFixture()
        let item = makeItemDTO(weight: 99_999_999)
        let group = makeGroupDTO(items: [item])
        let dto = makePackDTO(groups: [group])

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        let importedItem = pack.child.first?.child.first
        #expect(importedItem?.weight == APP_MAX_WEIGHT_NUM)
    }

    @Test("負の need は 0 にクランプされる")
    func negativeNeedIsClampedToZero() throws {
        let fx = try makeFixture()
        let item = makeItemDTO(need: -5)
        let group = makeGroupDTO(items: [item])
        let dto = makePackDTO(groups: [group])

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        let importedItem = pack.child.first?.child.first
        #expect(importedItem?.need == 0)
    }

    @Test("APP_MAX_STOCK_NUM を超える stock は上限にクランプされる")
    func excessiveStockIsClampedToMax() throws {
        let fx = try makeFixture()
        let item = makeItemDTO(stock: 99_999)
        let group = makeGroupDTO(items: [item])
        let dto = makePackDTO(groups: [group])

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        let importedItem = pack.child.first?.child.first
        #expect(importedItem?.stock == APP_MAX_STOCK_NUM)
    }

    // MARK: - 件数クランプ

    @Test("APP_MAX_PART_ROWS を超えるグループは先頭から切り捨てられる")
    func excessiveGroupsAreTruncated() throws {
        let fx = try makeFixture()
        // 50件のグループを用意（上限 30 を超える）
        let groups = (0..<50).map { i in
            makeGroupDTO(name: "G\(i)")
        }
        let dto = makePackDTO(groups: groups)

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        #expect(pack.child.count == APP_MAX_PART_ROWS)
        // 先頭から切り出されている（G0 が含まれる）
        let names = pack.child.sorted { $0.order < $1.order }.map(\.name)
        #expect(names.first == "G0")
    }

    @Test("APP_MAX_ITEM_ROWS を超えるアイテムは先頭から切り捨てられる")
    func excessiveItemsAreTruncated() throws {
        let fx = try makeFixture()
        // 200件のアイテムを持つグループ（上限 100 を超える）
        let items = (0..<200).map { i in
            makeItemDTO(name: "I\(i)")
        }
        let group = makeGroupDTO(items: items)
        let dto = makePackDTO(groups: [group])

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        let importedGroup = pack.child.first
        #expect(importedGroup?.child.count == APP_MAX_ITEM_ROWS)
    }

    // MARK: - 日付クランプ

    @Test("1990年以前の createdAt は現在時刻にフォールバックされる")
    func ancientCreatedAtFallsBackToNow() throws {
        let fx = try makeFixture()
        // 1970-01-02
        let ancientDate = Date(timeIntervalSince1970: 86400)
        let dto = makePackDTO(createdAt: ancientDate)

        let beforeImport = Date()
        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        let afterImport = Date()
        try fx.context.save()

        // フォールバックは現在時刻なので、import 前後の範囲に入る
        #expect(pack.createdAt >= beforeImport)
        #expect(pack.createdAt <= afterImport)
    }

    @Test("1年以上未来の createdAt は現在時刻にフォールバックされる")
    func farFutureCreatedAtFallsBackToNow() throws {
        let fx = try makeFixture()
        // 10年後
        let futureDate = Date().addingTimeInterval(10 * 365 * 24 * 60 * 60)
        let dto = makePackDTO(createdAt: futureDate)

        let beforeImport = Date()
        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        let afterImport = Date()
        try fx.context.save()

        #expect(pack.createdAt >= beforeImport)
        #expect(pack.createdAt <= afterImport)
    }

    @Test("妥当な範囲の createdAt はそのまま保持される")
    func validCreatedAtIsPreserved() throws {
        let fx = try makeFixture()
        // 2020-01-01
        let validDate = Date(timeIntervalSince1970: 1_577_836_800)
        let dto = makePackDTO(createdAt: validDate)

        let pack = PackImporter.insertPack(from: dto, into: fx.context, order: 0)
        try fx.context.save()
        #expect(pack.createdAt == validDate)
    }
}
