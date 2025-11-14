//
//  PackListTests.swift
//  PackListTests
//
//  Created by sumpo on 2025/09/05.
//

import Testing
import SwiftData
@testable import PackList

struct PackListTests {

    @Test("normalizeGroupOrder は order の乱れを解消して連番を維持する")
    func normalizeGroupOrderKeepsDisplaySequence() async throws {
        let pack = M1Pack(name: "Pack")
        let groupLate = M2Group(id: "late", name: "Late", order: 3)
        let groupTieA = M2Group(id: "a", name: "TieA", order: 1)
        let groupEarly = M2Group(id: "early", name: "Early", order: 1)

        pack.child = [groupLate, groupTieA, groupEarly]

        // 配列の順は触らず、order のみを正規化する
        pack.normalizeGroupOrder()
        // child 配列自体は変更されない
        #expect(pack.child.map(\.id) == ["late", "a", "early"])
        // order でソートすると order の連番が得られる
        let sorted = pack.child.sorted { $0.order < $1.order }
        #expect(sorted.map(\.id) == ["a", "early", "late"])
        for (index, group) in sorted.enumerated() {
            #expect(group.order == index * ORDER_SPARSE)
        }
    }

    @Test("normalizeItemOrder は order の乱れを解消して連番を維持する")
    func normalizeItemOrderKeepsDisplaySequence() async throws {
        let group = M2Group(name: "Group")
        let heavier = M3Item(id: "heavy", name: "Heavy", order: 2)
        let tie = M3Item(id: "mid", name: "Mid", order: 0)
        let lighter = M3Item(id: "light", name: "Light", order: 0)

        group.child = [heavier, tie, lighter]

        // 配列の順は触らず、order のみを正規化する
        group.normalizeItemOrder()
        // child 配列自体は変更されない
        #expect(group.child.map(\.id) == ["heavy", "mid", "light"])
        let sorted = group.child.sorted { $0.order < $1.order }
        #expect(sorted.map(\.id) == ["mid", "light", "heavy"])
        for (index, item) in sorted.enumerated() {
            #expect(item.order == index * ORDER_SPARSE)
        }
    }

    @Test("PackImporter.insertPack は order が衝突しても JSON 順を維持する")
    @MainActor
    func insertPackPreservesJsonOrderOnDuplicateOrders() throws {
        // In-MemoryのSwiftDataコンテナを用意し、JSON読み込み時の挙動を再現する
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: M1Pack.self, M2Group.self, M3Item.self, configurations: configuration)
        let context = container.mainContext

        // orderが同値なグループとアイテムをあえて用意し、並びがJSON順になることを検証する
        let dto = PackJsonDTO(
            productName: "Test",
            copyright: "Test",
            version: "1",
            id: nil,
            order: nil,
            name: "Sample",
            memo: "",
            createdAt: Date(),
            groups: [
                .init(
                    id: nil,
                    order: 100,
                    name: "GroupA",
                    memo: "",
                    items: [
                        .init(id: nil, order: 50, name: "ItemA1", memo: "", check: false, stock: nil, need: 1, weight: 0),
                        .init(id: nil, order: 50, name: "ItemA2", memo: "", check: false, stock: nil, need: 1, weight: 0)
                    ]
                ),
                .init(
                    id: nil,
                    order: 100,
                    name: "GroupB",
                    memo: "",
                    items: [
                        .init(id: nil, order: 0, name: "ItemB1", memo: "", check: false, stock: nil, need: 1, weight: 0)
                    ]
                ),
                .init(
                    id: nil,
                    order: 100,
                    name: "GroupC",
                    memo: "",
                    items: [
                        .init(id: nil, order: nil, name: "ItemC1", memo: "", check: false, stock: nil, need: 1, weight: 0)
                    ]
                )
            ]
        )

        let pack = PackImporter.insertPack(from: dto, into: context, order: 0)

        // order採番後でもJSON順が保たれているかチェックする
        let groupNames = pack.child.sorted { $0.order < $1.order }.map { $0.name }
        #expect(groupNames == ["GroupA", "GroupB", "GroupC"])

        let firstGroupItems = pack.child.first?.child.sorted { $0.order < $1.order }.map { $0.name } ?? []
        #expect(firstGroupItems == ["ItemA1", "ItemA2"])
    }
}

