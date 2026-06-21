//
//  OrderAllocationTests.swift
//  PackListTests
//
//  Fix 6（duplicate() の order 一時衝突）の動作検証。
//  - 自分の直後に正しく挿入される
//  - 隣接 order が +1 でも衝突しない
//  - 連続複製で順序が崩れない
//  - 末尾複製は最後尾に追加される
//

import Testing
import Foundation
import SwiftData
@testable import Packlin

@MainActor
struct OrderAllocationTests {

    // MARK: - Fixture

    /// テストで参照するオブジェクト群を保持する構造体。
    /// container をフィールドに持つことでスコープ外で解放されないようにする
    /// （ModelContext は ModelContainer の弱参照になる可能性があるため、
    ///  ModelContainer を強く保持しておくと SwiftData の fetch が安定する）。
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let packA: M1Pack
        let packB: M1Pack
        let packC: M1Pack
    }

    private func makeFixtureWithThreePacks() throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context = container.mainContext

        // 0, 1000, 2000 の通常スパース配置
        let packA = M1Pack(id: "A", name: "PackA", order: 0)
        let packB = M1Pack(id: "B", name: "PackB", order: ORDER_SPARSE)
        let packC = M1Pack(id: "C", name: "PackC", order: ORDER_SPARSE * 2)
        context.insert(packA)
        context.insert(packB)
        context.insert(packC)
        // テスト開始時の状態を永続化しておくと、duplicate() 中の fetch が安定する
        try context.save()

        return Fixture(container: container, context: context,
                       packA: packA, packB: packB, packC: packC)
    }

    /// order でソートした FetchDescriptor を返す共通ヘルパー。
    /// Swift の `.sorted` ではなく SortDescriptor を使う方が SwiftData では安定する。
    private func sortedPackDescriptor() -> FetchDescriptor<M1Pack> {
        FetchDescriptor<M1Pack>(sortBy: [SortDescriptor(\.order, order: .forward)])
    }

    // MARK: - M1Pack.duplicate()

    @Test("Pack.duplicate は元の Pack の直後に新 Pack を配置する")
    func duplicatePackInsertsImmediatelyAfterOriginal() throws {
        let fx = try makeFixtureWithThreePacks()

        // PackB を複製 → 期待される並びは [A, B, B', C]
        fx.packB.duplicate()
        try fx.context.save()

        let allPacks = try fx.context.fetch(sortedPackDescriptor())
        #expect(allPacks.count == 4)
        let names = allPacks.map(\.name)
        #expect(names == ["PackA", "PackB", "PackB", "PackC"])
    }

    @Test("隣接 order が +1 でも duplicate は衝突せず正しく挿入される")
    func duplicateHandlesAdjacentOrderWithoutCollision() throws {
        // 個別にコンテナを作る（密配置の特殊ケース）
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context = container.mainContext

        // order が密に詰まったケース：5, 6, 7
        // 旧版 (self.order + 1) なら衝突するシナリオ
        let pA = M1Pack(id: "A", name: "PackA", order: 5)
        let pB = M1Pack(id: "B", name: "PackB", order: 6)
        let pC = M1Pack(id: "C", name: "PackC", order: 7)
        context.insert(pA)
        context.insert(pB)
        context.insert(pC)
        try context.save()

        // PackA を複製 → 旧版なら order=6 になり PackB と衝突。
        // 新版は sparseOrderForInsertion で衝突を回避する。
        pA.duplicate()
        try context.save()

        let allPacks = try context.fetch(
            FetchDescriptor<M1Pack>(sortBy: [SortDescriptor(\.order, order: .forward)])
        )
        // 4 件あり、order がすべてユニークであること
        #expect(allPacks.count == 4)
        let orders = allPacks.map(\.order)
        #expect(Set(orders).count == orders.count, "order が衝突している: \(orders)")
        // 並び順は [PackA, PackA(複製), PackB, PackC]
        let names = allPacks.map(\.name)
        #expect(names == ["PackA", "PackA", "PackB", "PackC"])
        // container を明示的に最後まで保持する
        _ = container
    }

    @Test("末尾の Pack を複製すると最後尾に新 Pack が追加される")
    func duplicateLastPackAppendsToEnd() throws {
        let fx = try makeFixtureWithThreePacks()

        fx.packC.duplicate()
        try fx.context.save()

        let allPacks = try fx.context.fetch(sortedPackDescriptor())
        #expect(allPacks.count == 4)
        let names = allPacks.map(\.name)
        #expect(names == ["PackA", "PackB", "PackC", "PackC"])
        // 末尾 2 件はどちらも PackC で、order が異なる
        #expect(allPacks[2].order < allPacks[3].order)
    }

    @Test("同一 Pack を 5 連続複製しても順序が崩れず order が全てユニークになる")
    func consecutiveDuplicationsKeepOrderConsistent() throws {
        let fx = try makeFixtureWithThreePacks()

        // PackB を 5 回連続複製。各複製後に save して内部状態を安定させる
        for _ in 0..<5 {
            fx.packB.duplicate()
            try fx.context.save()
        }

        let allPacks = try fx.context.fetch(sortedPackDescriptor())
        // 元 3 件 + 複製 5 件 = 8 件
        #expect(allPacks.count == 8)
        // すべての order がユニーク（衝突なし）
        let orders = allPacks.map(\.order)
        #expect(Set(orders).count == orders.count, "連続複製で order が衝突した: \(orders)")
        // PackA は先頭、PackC は末尾、その間は PackB が 6 件並ぶ
        #expect(allPacks.first?.name == "PackA")
        #expect(allPacks.last?.name == "PackC")
        let middle = Array(allPacks[1..<7])
        #expect(middle.allSatisfy { $0.name == "PackB" })
    }

    // MARK: - M2Group.duplicate()

    @Test("Group.duplicate は親パック配下で元の Group の直後に配置される")
    func duplicateGroupInsertsImmediatelyAfterOriginal() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context = container.mainContext

        let pack = M1Pack(id: "P", name: "Pack", order: 0)
        context.insert(pack)
        let g1 = M2Group(id: "G1", name: "G1", order: 0, parent: pack)
        let g2 = M2Group(id: "G2", name: "G2", order: ORDER_SPARSE, parent: pack)
        let g3 = M2Group(id: "G3", name: "G3", order: ORDER_SPARSE * 2, parent: pack)
        context.insert(g1)
        context.insert(g2)
        context.insert(g3)
        try context.save()

        // G2 を複製 → 期待される並びは [G1, G2, G2', G3]
        g2.duplicate()
        try context.save()

        let groupDescriptor = FetchDescriptor<M2Group>(sortBy: [SortDescriptor(\.order, order: .forward)])
        let sortedGroups = try context.fetch(groupDescriptor)
        #expect(sortedGroups.count == 4)
        #expect(sortedGroups.map(\.name) == ["G1", "G2", "G2", "G3"])
        let orders = sortedGroups.map(\.order)
        #expect(Set(orders).count == orders.count)
        _ = container
    }

    // MARK: - M3Item.duplicate()

    @Test("Item.duplicate は親グループ配下で元の Item の直後に配置される")
    func duplicateItemInsertsImmediatelyAfterOriginal() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context = container.mainContext

        let pack = M1Pack(id: "P", name: "Pack", order: 0)
        context.insert(pack)
        let group = M2Group(id: "G", name: "G", order: 0, parent: pack)
        context.insert(group)
        let i1 = M3Item(id: "I1", name: "I1", order: 0, parent: group)
        let i2 = M3Item(id: "I2", name: "I2", order: ORDER_SPARSE, parent: group)
        let i3 = M3Item(id: "I3", name: "I3", order: ORDER_SPARSE * 2, parent: group)
        context.insert(i1)
        context.insert(i2)
        context.insert(i3)
        try context.save()

        // I2 を複製
        i2.duplicate()
        try context.save()

        let itemDescriptor = FetchDescriptor<M3Item>(sortBy: [SortDescriptor(\.order, order: .forward)])
        let sortedItems = try context.fetch(itemDescriptor)
        #expect(sortedItems.count == 4)
        #expect(sortedItems.map(\.name) == ["I1", "I2", "I2", "I3"])
        let orders = sortedItems.map(\.order)
        #expect(Set(orders).count == orders.count)
        _ = container
    }

    @Test("Item.duplicate で複製したアイテムは check=false かつ stock=0 にリセットされる")
    func duplicatedItemHasResetProgressFields() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context = container.mainContext

        let pack = M1Pack(id: "P", name: "Pack", order: 0)
        context.insert(pack)
        let group = M2Group(id: "G", name: "G", order: 0, parent: pack)
        context.insert(group)
        // 進捗データが入った Item を用意
        let original = M3Item(id: "I1", name: "Original",
                              check: true, stock: 5, need: 10, weight: 200,
                              order: 0, parent: group)
        context.insert(original)
        try context.save()

        original.duplicate()
        try context.save()

        // 複製後の Item を id 以外で探す
        let items = try context.fetch(FetchDescriptor<M3Item>())
        let duplicated = items.first { $0.id != "I1" }
        #expect(duplicated != nil)
        // 元の属性はコピーされている
        #expect(duplicated?.name == "Original")
        #expect(duplicated?.need == 10)
        #expect(duplicated?.weight == 200)
        // 進捗系はリセットされている
        #expect(duplicated?.check == false)
        #expect(duplicated?.stock == 0)
        _ = container
    }
}
