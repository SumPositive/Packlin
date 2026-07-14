//
//  PerformanceTests.swift
//  PackListTests
//
//  集計・Export/Import の効率性に関する参考計測。
//  許容時間は十分緩めに設定（CI / シミュレータ間の差を吸収するため）。
//  厳密な計測ではなく「明らかにおかしくなったら気付ける」目的のスモークテスト。
//

import Testing
import Foundation
import SwiftData
@testable import Packlin

@MainActor
struct PerformanceTests {

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

    /// `groupsPerPack` × `itemsPerGroup` のフル構造を持つ `packCount` 個の Pack を作って save する
    /// - Returns: 作成されたパックの配列
    @discardableResult
    private func seedLargeDataset(
        in context: ModelContext,
        packCount: Int,
        groupsPerPack: Int,
        itemsPerGroup: Int
    ) throws -> [M1Pack] {
        var packs: [M1Pack] = []
        for p in 0..<packCount {
            let pack = M1Pack(
                id: "P\(p)",
                name: "Pack\(p)",
                order: p * ORDER_SPARSE
            )
            context.insert(pack)
            for g in 0..<groupsPerPack {
                let group = M2Group(
                    id: "P\(p)-G\(g)",
                    name: "Group\(g)",
                    order: g * ORDER_SPARSE,
                    parent: pack
                )
                context.insert(group)
                for i in 0..<itemsPerGroup {
                    let item = M3Item(
                        id: "P\(p)-G\(g)-I\(i)",
                        name: "Item\(i)",
                        check: i % 2 == 0,
                        stock: i % 10,
                        need: 5,
                        weight: 100 + i,
                        order: i * ORDER_SPARSE,
                        parent: group
                    )
                    context.insert(item)
                }
            }
            packs.append(pack)
        }
        try context.save()
        return packs
    }

    /// 経過時間（秒）を返すヘルパー
    private func measure(_ block: () throws -> Void) rethrows -> Double {
        let start = Date()
        try block()
        return Date().timeIntervalSince(start)
    }

    // MARK: - 集計性能

    @Test("中規模データ（10 Pack × 10 Group × 50 Item）の stockWeight 集計が 5 秒以内に終わる")
    func aggregateStockWeightFinishesQuickly() throws {
        let fx = try makeFixture()
        // 合計 5,000 Item の中規模データ
        // 注：APP_MAX 上限値（30×30×100=90,000 Item）はシミュレータの SwiftData lazy load では
        // 数秒〜十数秒かかるため、実用的な「中規模」サイズで集計性能を検証する。
        let packs = try seedLargeDataset(
            in: fx.context,
            packCount: 10,
            groupsPerPack: 10,
            itemsPerGroup: 50
        )

        var totalStockWeight = 0
        var totalNeedWeight = 0
        let elapsed = measure {
            for pack in packs {
                totalStockWeight += pack.stockWeight
                totalNeedWeight += pack.needWeight
            }
        }

        // 集計値が 0 ではないことを確認（計算が空回ししていない）
        #expect(totalStockWeight > 0)
        #expect(totalNeedWeight > 0)
        // CI / シミュレータ差を吸収するため十分余裕を持たせる
        #expect(elapsed < 5.0, "集計に \(elapsed) 秒かかった（許容 5.0 秒）")
    }

    // MARK: - Export / Import ラウンドトリップ性能

    @Test("中規模データ（10 Pack × 10 Group × 50 Item）の Export → Import が 3 秒以内に完了する")
    func exportImportRoundtripFinishesQuickly() throws {
        let fx = try makeFixture()
        // 5,000 Item ぶんの中規模データ
        let packs = try seedLargeDataset(
            in: fx.context,
            packCount: 10,
            groupsPerPack: 10,
            itemsPerGroup: 50
        )

        // === Export 計測 ===
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var encodedSize = 0
        let exportTime = try measure {
            for pack in packs {
                let dto = pack.exportRepresentation()
                let data = try encoder.encode(dto)
                encodedSize += data.count
            }
        }

        // === Import 計測（別コンテナへ）===
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container2 = try ModelContainer(
            for: M1Pack.self, M2Group.self, M3Item.self,
            configurations: configuration
        )
        let context2 = container2.mainContext

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let importTime = try measure {
            for (index, pack) in packs.enumerated() {
                let dto = pack.exportRepresentation()
                let data = try encoder.encode(dto)
                let decoded = try decoder.decode(PackJsonDTO.self, from: data)
                PackImporter.insertPack(from: decoded, into: context2, order: index * ORDER_SPARSE)
            }
            try context2.save()
        }

        let totalTime = exportTime + importTime
        #expect(encodedSize > 0)
        #expect(totalTime < 3.0,
                "Export+Import 合計 \(totalTime) 秒（許容 3.0 秒）。Export: \(exportTime), Import: \(importTime)")
        _ = container2
    }

    // MARK: - 大量 insert / delete サイクル性能

    @Test("100 Pack の insert と delete サイクルが 5 秒以内に完了する")
    func insertDeleteCycleFinishesQuickly() throws {
        let fx = try makeFixture()

        let elapsed = try measure {
            // 100 個の Pack を一気に追加
            for p in 0..<100 {
                let pack = M1Pack(
                    id: "P\(p)",
                    name: "Pack\(p)",
                    order: p * ORDER_SPARSE
                )
                fx.context.insert(pack)
            }
            try fx.context.save()

            // 全部削除（cascade なしで Pack だけ）
            let descriptor = FetchDescriptor<M1Pack>()
            let all = try fx.context.fetch(descriptor)
            for pack in all {
                pack.delete()
            }
            try fx.context.save()
        }

        // 削除後は 0 件
        let remaining = try fx.context.fetch(FetchDescriptor<M1Pack>())
        #expect(remaining.isEmpty)
        #expect(elapsed < 5.0, "insert + delete サイクルに \(elapsed) 秒かかった（許容 5.0 秒）")
    }
}
