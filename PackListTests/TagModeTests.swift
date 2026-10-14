//
//  TagModeTests.swift
//  PackListTests
//
//  タグ式まわりの検証。壊れても画面では気付きにくいところを押さえる。
//  - 書き出し→取り込みで、分類方式とタグ式グループが引き継がれる
//  - 旧形式（分類方式なし）はグループ式として取り込まれる
//  - パック複製でタグ式グループの役割が新しいグループへ移る
//  - グループ式→タグ式の切り替えで、グループ名がタグになる（タグ式グループと空の名前は対象外）
//  - タグ一覧の詰め込み（AZFlowLayout）の行分けと、配置時に使う幅
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
@testable import Packlin

@MainActor
struct TagModeTests {

    // MARK: - Fixture

    /// container を強参照で保持する（解放されると SwiftData の insert/fetch が trap する）
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

    /// タグ式のパック: 「衣類」グループ [シャツ] と「タグ式グループ」 [歯ブラシ]
    @discardableResult
    private func makeTagModePack(in context: ModelContext) -> M1Pack {
        let pack = M1Pack(name: "Trip", order: 0)
        pack.classifyMode = .tag
        context.insert(pack)

        let clothes = M2Group(name: "衣類", order: 0, parent: pack)
        context.insert(clothes)
        context.insert(M3Item(name: "シャツ", tags: ["衣類", "必須"], order: 0, parent: clothes))

        let tagGroup = M2Group(name: "タグ式グループ", order: ORDER_SPARSE, parent: pack)
        context.insert(tagGroup)
        pack.tagModeGroupID = tagGroup.id
        context.insert(M3Item(name: "歯ブラシ", tags: ["ケア"], order: 0, parent: tagGroup))
        return pack
    }

    /// DTO を JSON にして戻す（共有ファイル・公開パックと同じ往復）
    private func roundTrip(_ dto: PackJsonDTO) throws -> PackJsonDTO {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PackJsonDTO.self, from: encoder.encode(dto))
    }

    // MARK: - 書き出し → 取り込み

    @Test("書き出し→取り込みで分類方式とタグ式グループが引き継がれる")
    func exportImportKeepsTagMode() throws {
        let f = try makeFixture()
        let source = makeTagModePack(in: f.context)

        let dto = try roundTrip(source.exportRepresentation())
        #expect(dto.classifyMode == "tag")
        #expect(dto.groups.map { $0.isTagModeGroup } == [nil, true])

        let imported = PackImporter.insertPack(from: dto, into: f.context, order: ORDER_SPARSE)
        #expect(imported.classifyMode == .tag)
        let tagGroup = try #require(imported.child.first { $0.id == imported.tagModeGroupID })
        #expect(tagGroup.name == "タグ式グループ")
        // 取り込み先では新しい ID になる（元のグループ ID を指したままにならない）
        #expect(imported.tagModeGroupID != source.tagModeGroupID)
        // タグもそのまま
        let shirt = try #require(imported.child.flatMap(\.child).first { $0.name == "シャツ" })
        #expect(shirt.tags == ["衣類", "必須"])
    }

    @Test("バックアップの書き出しも分類方式を含む")
    func backupKeepsTagMode() throws {
        let f = try makeFixture()
        let source = makeTagModePack(in: f.context)
        let dto = try roundTrip(source.backupRepresentation())
        #expect(dto.classifyMode == "tag")
        #expect(dto.groups.contains { $0.isTagModeGroup == true })
    }

    @Test("旧形式（分類方式なし）はグループ式として取り込まれる")
    func legacyDTOImportsAsGroupMode() throws {
        let f = try makeFixture()
        let source = makeTagModePack(in: f.context)
        var dto = source.exportRepresentation()
        dto.classifyMode = nil
        // 旧形式にはタグ式グループの印も無い
        let legacyGroups = dto.groups.map { group -> PackJsonDTO.Group in
            var g = group
            g.isTagModeGroup = nil
            return g
        }
        let legacy = PackJsonDTO(productName: dto.productName, copyright: dto.copyright, version: dto.version,
                                 id: nil, order: nil, name: dto.name, memo: dto.memo,
                                 createdAt: dto.createdAt, groups: legacyGroups)

        let imported = PackImporter.insertPack(from: try roundTrip(legacy), into: f.context, order: ORDER_SPARSE)
        #expect(imported.classifyMode == .group)
        #expect(imported.classifyModeRaw == nil)
        #expect(imported.tagModeGroupID == nil)
    }

    @Test("上書き取り込みで分類方式とタグ式グループが入れ替わる")
    func overwriteReplacesTagMode() throws {
        let f = try makeFixture()
        let target = makeTagModePack(in: f.context)

        // グループ式のパックで上書きすると、タグ式の印は消える
        let groupPack = M1Pack(name: "Group", order: 0)
        f.context.insert(groupPack)
        let g = M2Group(name: "G", order: 0, parent: groupPack)
        f.context.insert(g)
        f.context.insert(M3Item(name: "I", order: 0, parent: g))

        PackImporter.overwrite(pack: target, with: try roundTrip(groupPack.exportRepresentation()), in: f.context)
        #expect(target.classifyMode == .group)
        #expect(target.tagModeGroupID == nil)
    }

    // MARK: - 複製

    @Test("パック複製でタグ式グループの役割が新しいグループへ移る")
    func duplicateKeepsTagModeGroup() throws {
        let f = try makeFixture()
        let source = makeTagModePack(in: f.context)
        try f.context.save()

        source.duplicate()
        let packs = try f.context.fetch(FetchDescriptor<M1Pack>())
        let copy = try #require(packs.first { $0.id != source.id })
        #expect(copy.classifyMode == .tag)
        let copiedTagGroup = try #require(copy.child.first { $0.id == copy.tagModeGroupID })
        #expect(copiedTagGroup.name == "タグ式グループ")
        #expect(copy.tagModeGroupID != source.tagModeGroupID)
    }

    // MARK: - グループ式 → タグ式

    @Test("グループ名がタグになる（タグ式グループと空の名前は対象外・何度でも重複しない）")
    func groupNamesBecomeTags() throws {
        let f = try makeFixture()
        let pack = M1Pack(name: "P", order: 0)
        f.context.insert(pack)

        let named = M2Group(name: "電子機器", order: 0, parent: pack)
        f.context.insert(named)
        let pc = M3Item(name: "PC", tags: ["仕事"], order: 0, parent: named)
        f.context.insert(pc)

        let unnamed = M2Group(name: "", order: ORDER_SPARSE, parent: pack)
        f.context.insert(unnamed)
        let pen = M3Item(name: "ペン", order: 0, parent: unnamed)
        f.context.insert(pen)

        let tagGroup = M2Group(name: "タグ式グループ", order: ORDER_SPARSE * 2, parent: pack)
        f.context.insert(tagGroup)
        pack.tagModeGroupID = tagGroup.id
        let brush = M3Item(name: "歯ブラシ", order: 0, parent: tagGroup)
        f.context.insert(brush)

        pack.tagItemsWithGroupNames()
        pack.tagItemsWithGroupNames()   // 2回目でも重複しない

        #expect(pc.tags == ["仕事", "電子機器"])
        #expect(pen.tags.isEmpty)
        #expect(brush.tags.isEmpty)
    }

    // MARK: - タグ一覧の詰め込み（AZFlowLayout）

    private func sizes(_ widths: [CGFloat]) -> [CGSize] {
        widths.map { CGSize(width: $0, height: 30) }
    }

    @Test("行末の空きに、後ろの収まる要素を繰り上げる")
    func packToFillMovesLaterItemUp() {
        let layout = AZFlowLayout(spacing: 10, rowSpacing: 8, alignment: .leading, packToFill: true)
        // 80 の後ろの空きは 200-80-10=110。150 は入らないが、その後ろの 60 は入る
        let rows = layout.makeRows(sizes: sizes([80, 150, 60]), availableWidth: 200)
        #expect(rows == [[0, 2], [1]])
    }

    @Test("繰り上げなしなら並び順どおりに折り返す")
    func withoutPackToFillKeepsOrder() {
        let layout = AZFlowLayout(spacing: 10, rowSpacing: 8, alignment: .leading, packToFill: false)
        let rows = layout.makeRows(sizes: sizes([80, 150, 60]), availableWidth: 200)
        #expect(rows == [[0], [1], [2]])
    }

    @Test("配置の行分けは、提案された幅（sizeThatFits と同じ幅）で行う")
    func placementUsesProposedWidth() {
        let layout = AZFlowLayout(spacing: 10, rowSpacing: 8, alignment: .leading, packToFill: true)
        let s = sizes([100, 120, 60, 200])
        // 提案幅 300 での行分け: [100, 120, 60] = 300 と [200]。sizeThatFits はこの最長行 300 を返すが、
        // 中身の幅が 290 の例として、bounds が提案より狭く渡されても行分けが変わらないこと
        let proposed: CGFloat = 300
        let rowsAtProposal = layout.makeRows(sizes: s, availableWidth: proposed)
        let width = AZFlowLayout.placementWidth(boundsWidth: 290, proposalWidth: proposed)
        #expect(width == proposed)
        #expect(layout.makeRows(sizes: s, availableWidth: width) == rowsAtProposal)
        // bounds の幅で分け直すと行が変わってしまう（このずれが以前の不具合）
        #expect(layout.makeRows(sizes: s, availableWidth: 290) != rowsAtProposal)
    }

    @Test("提案幅が無いか無限大のときは bounds の幅を使う")
    func placementFallsBackToBounds() {
        #expect(AZFlowLayout.placementWidth(boundsWidth: 250, proposalWidth: nil) == 250)
        #expect(AZFlowLayout.placementWidth(boundsWidth: 250, proposalWidth: .infinity) == 250)
    }
}
