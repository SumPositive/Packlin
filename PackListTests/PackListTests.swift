//
//  PackListTests.swift
//  PackListTests
//
//  Created by sumpo on 2025/09/05.
//

import Testing
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

}
