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
        let groupEarly = M2Group(id: "early", name: "Early", order: 1)
        let groupTieA = M2Group(id: "a", name: "TieA", order: 1)

        pack.child = [groupLate, groupTieA, groupEarly]

        pack.normalizeGroupOrder()

        #expect(pack.child.map(\.id) == ["a", "early", "late"])
        for (index, group) in pack.child.enumerated() {
            #expect(group.order == index)
        }
    }

    @Test("normalizeItemOrder は order の乱れを解消して連番を維持する")
    func normalizeItemOrderKeepsDisplaySequence() async throws {
        let group = M2Group(name: "Group")
        let heavier = M3Item(id: "heavy", name: "Heavy", order: 2)
        let lighter = M3Item(id: "light", name: "Light", order: 0)
        let tie = M3Item(id: "mid", name: "Mid", order: 0)

        group.child = [heavier, tie, lighter]

        group.normalizeItemOrder()

        #expect(group.child.map(\.id) == ["light", "mid", "heavy"])
        for (index, item) in group.child.enumerated() {
            #expect(item.order == index)
        }
    }

}
