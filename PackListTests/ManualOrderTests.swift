//
//  ManualOrderTests.swift
//  PackListTests
//
//  アイテム縦覧の「指定順」（タグ式）のドラッグ移動の検証。
//  - 指定順は「グループの順 → グループ内のアイテムの順」
//  - 移動したアイテムは、入れた位置の直前のアイテムのグループへ移る（先頭なら直後のアイテムのグループ）
//  - 絞り込み中は「見えている直前の行の直後」へ入れ、見えない行どうしの順番は変えない
//

import Testing
import Foundation
import SwiftData
@testable import Packlin

@MainActor
struct ManualOrderTests {

    // MARK: - Fixture

    /// container を強参照で保持する（解放されると SwiftData の insert/fetch が trap する）
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let pack: M1Pack
        let first: M2Group
        let second: M2Group
    }

    /// タグ式のパック: G1 [A(x), B(y)] と G2 [C(x), D(y)]。指定順は A B C D
    private func makeFixture() throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context = container.mainContext
        let pack = M1Pack(name: "Trip", order: 0)
        pack.classifyMode = .tag
        context.insert(pack)

        let first = M2Group(name: "G1", order: 0, parent: pack)
        context.insert(first)
        context.insert(M3Item(name: "A", tags: ["x"], order: 0, parent: first))
        context.insert(M3Item(name: "B", tags: ["y"], order: ORDER_SPARSE, parent: first))

        let second = M2Group(name: "G2", order: ORDER_SPARSE, parent: pack)
        context.insert(second)
        context.insert(M3Item(name: "C", tags: ["x"], order: 0, parent: second))
        context.insert(M3Item(name: "D", tags: ["y"], order: ORDER_SPARSE, parent: second))
        return Fixture(container: container, context: context, pack: pack, first: first, second: second)
    }

    private func names(_ items: [M3Item]) -> [String] {
        items.map(\.name)
    }

    private func names(of group: M2Group) -> [String] {
        names(group.child.sorted { $0.order < $1.order })
    }

    private func visible(_ pack: M1Pack, tag: String?) -> [M3Item] {
        let items = pack.itemsInManualOrder
        guard let tag else { return items }
        return items.filter { $0.tags.contains(tag) }
    }

    // MARK: - 指定順

    @Test("指定順はグループの順、グループ内のアイテムの順に並ぶ")
    func manualOrderFollowsGroupThenItemOrder() throws {
        let f = try makeFixture()
        #expect(names(f.pack.itemsInManualOrder) == ["A", "B", "C", "D"])
        #expect(names(ItemSortOption.manual.sortedItems(from: f.pack, reversed: true)) == ["A", "B", "C", "D"])
    }

    @Test("指定順のタグは、先に出てくるアイテムのタグから並び、アイテムを動かすと付いてくる")
    func tagsFollowManualItemOrder() throws {
        let f = try makeFixture()
        #expect(f.pack.tagsInManualOrder == ["x", "y"])

        // D(y) を先頭へ動かすと、y が先頭になる
        f.pack.moveItemsInManualOrder(visible: visible(f.pack, tag: nil), from: [3], to: 0)
        #expect(f.pack.tagsInManualOrder == ["y", "x"])
    }

    @Test("1つのアイテムに新しいタグが複数あるときは、アイテム数の多い順に並ぶ")
    func tagsOnSameItemFollowItemCount() throws {
        let f = try makeFixture()
        // 先頭の A に「少」「多」を足す。「多」は B にも付けて2件にする
        let items = f.pack.itemsInManualOrder
        items[0].tags = ["少", "多", "x"]
        items[1].tags = ["y", "多"]

        // A の新しいタグは x(2件)・多(2件)・少(1件)。同数の x と 多 は A での並び（多 → x）のまま
        #expect(f.pack.tagsInManualOrder == ["多", "x", "少", "y"])
    }

    // MARK: - 絞り込みなし

    @Test("先頭へ動かすと、直後のアイテムのグループに入る")
    func moveToTopJoinsNextGroup() throws {
        let f = try makeFixture()
        f.pack.moveItemsInManualOrder(visible: visible(f.pack, tag: nil), from: [3], to: 0)

        #expect(names(f.pack.itemsInManualOrder) == ["D", "A", "B", "C"])
        #expect(names(of: f.first) == ["D", "A", "B"])
        #expect(names(of: f.second) == ["C"])
    }

    @Test("グループの境目に落とすと、直前のアイテムのグループに入る")
    func dropOnBoundaryJoinsPreviousGroup() throws {
        let f = try makeFixture()
        // B と C の間（直前は G1 の B）
        f.pack.moveItemsInManualOrder(visible: visible(f.pack, tag: nil), from: [3], to: 2)

        #expect(names(f.pack.itemsInManualOrder) == ["A", "B", "D", "C"])
        #expect(names(of: f.first) == ["A", "B", "D"])
        #expect(names(of: f.second) == ["C"])
    }

    @Test("下へ動かすと、落とした位置の直前のアイテムの後ろに入る")
    func moveDownPlacesAfterPreviousRow() throws {
        let f = try makeFixture()
        // A を C と D の間へ
        f.pack.moveItemsInManualOrder(visible: visible(f.pack, tag: nil), from: [0], to: 3)

        #expect(names(f.pack.itemsInManualOrder) == ["B", "C", "A", "D"])
        #expect(names(of: f.first) == ["B"])
        #expect(names(of: f.second) == ["C", "A", "D"])
    }

    // MARK: - 絞り込み中

    @Test("絞り込み中に先頭へ動かすと、見えている先頭の行の直前に入る")
    func filteredMoveToTopPlacesBeforeFirstVisible() throws {
        let f = try makeFixture()
        // タグ x で絞り込み: [A, C]。C を先頭へ
        f.pack.moveItemsInManualOrder(visible: visible(f.pack, tag: "x"), from: [1], to: 0)

        #expect(names(f.pack.itemsInManualOrder) == ["C", "A", "B", "D"])
        #expect(names(of: f.first) == ["C", "A", "B"])
        #expect(names(of: f.second) == ["D"])
    }

    @Test("絞り込み中に末尾へ動かすと、見えている最後の行の直後に入り、見えない行は動かない")
    func filteredMoveToEndPlacesAfterLastVisible() throws {
        let f = try makeFixture()
        // タグ x で絞り込み: [A, C]。A を末尾へ（見えない D より前、C の直後）
        f.pack.moveItemsInManualOrder(visible: visible(f.pack, tag: "x"), from: [0], to: 2)

        #expect(names(f.pack.itemsInManualOrder) == ["B", "C", "A", "D"])
        #expect(names(of: f.second) == ["C", "A", "D"])
    }

    @Test("見えている行が動かすものだけなら何もしない")
    func singleVisibleRowDoesNothing() throws {
        let f = try makeFixture()
        let only = [try #require(f.pack.itemsInManualOrder.first)]
        f.pack.moveItemsInManualOrder(visible: only, from: [0], to: 1)

        #expect(names(f.pack.itemsInManualOrder) == ["A", "B", "C", "D"])
    }
}
