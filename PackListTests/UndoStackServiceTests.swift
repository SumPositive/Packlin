//
//  UndoStackServiceTests.swift
//  PackListTests
//
//  Fix 8（Group/Item の Pack 越境）と Fix 10（transactionDepth リセット）の動作検証。
//  - 基本的な undo / redo の往復
//  - Group を別 Pack に移動 → undo で元 Pack に戻ること
//  - Item を別 Group に移動 → undo で元 Group に戻ること
//  - transactionDepth の不変条件（負にならない）
//  - スタブな groupingEnd を吸収できること
//

import Testing
import Foundation
import SwiftData
@testable import Packlin

@MainActor
struct UndoStackServiceTests {

    // MARK: - Helpers

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let service: UndoStackService
    }

    private func makeFixture() throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: M1Pack.self, M2Group.self, M3Item.self, configurations: configuration)
        let context = container.mainContext
        let service = UndoStackService(maxStackSize: 10)
        return Fixture(container: container, context: context, service: service)
    }

    /// Pack A (G1 [I1, I2]) + Pack B (G2) という初期状態を作る
    /// - 末尾で `context.save()` を呼んで内部状態を確定させる
    ///   （SwiftData の fetch は未保存変更があると挙動が不安定になりがち）
    private func seedTwoPacks(in context: ModelContext) -> (M1Pack, M1Pack, M2Group, M2Group, M3Item, M3Item) {
        let packA = M1Pack(id: "PA", name: "PackA", order: 0)
        let packB = M1Pack(id: "PB", name: "PackB", order: ORDER_SPARSE)
        context.insert(packA)
        context.insert(packB)

        let g1 = M2Group(id: "G1", name: "G1", order: 0, parent: packA)
        let g2 = M2Group(id: "G2", name: "G2", order: 0, parent: packB)
        context.insert(g1)
        context.insert(g2)

        let i1 = M3Item(id: "I1", name: "I1", order: 0, parent: g1)
        let i2 = M3Item(id: "I2", name: "I2", order: ORDER_SPARSE, parent: g1)
        context.insert(i1)
        context.insert(i2)

        // 初期データを永続化してから返す。これにより fetch が安定する
        try? context.save()

        return (packA, packB, g1, g2, i1, i2)
    }

    // MARK: - 基本動作

    @Test("初期状態では canUndo / canRedo はどちらも false")
    func initialStateHasNoHistory() throws {
        let fx = try makeFixture()
        _ = seedTwoPacks(in: fx.context)

        #expect(fx.service.canUndo == false)
        #expect(fx.service.canRedo == false)
    }

    @Test("perform で 1 操作実行すると canUndo が true になる")
    func performEnablesUndo() throws {
        let fx = try makeFixture()
        let (packA, _, _, _, _, _) = seedTwoPacks(in: fx.context)

        fx.service.perform(context: fx.context) {
            packA.name = "PackA-Edited"
        }

        #expect(fx.service.canUndo == true)
        #expect(fx.service.canRedo == false)
    }

    @Test("Undo すると変更前の状態に戻る")
    func undoRevertsChanges() throws {
        let fx = try makeFixture()
        let (packA, _, _, _, _, _) = seedTwoPacks(in: fx.context)
        let originalName = packA.name

        fx.service.perform(context: fx.context) {
            packA.name = "Edited"
        }
        #expect(packA.name == "Edited")

        fx.service.undo(context: fx.context)

        // 名前が元に戻っている
        let packs = try fx.context.fetch(FetchDescriptor<M1Pack>())
        let restored = packs.first { $0.id == "PA" }
        #expect(restored?.name == originalName)
        #expect(fx.service.canUndo == false)
        #expect(fx.service.canRedo == true)
    }

    @Test("Undo 後の Redo で変更後の状態に戻る")
    func redoReappliesChanges() throws {
        let fx = try makeFixture()
        let (packA, _, _, _, _, _) = seedTwoPacks(in: fx.context)

        fx.service.perform(context: fx.context) {
            packA.name = "Edited"
        }
        fx.service.undo(context: fx.context)
        fx.service.redo(context: fx.context)

        let packs = try fx.context.fetch(FetchDescriptor<M1Pack>())
        let restored = packs.first { $0.id == "PA" }
        #expect(restored?.name == "Edited")
        #expect(fx.service.canUndo == true)
        #expect(fx.service.canRedo == false)
    }

    // MARK: - Fix 8: Pack 越境

    @Test("Group の Pack 越境（A→B）を Undo すると元の Pack A に戻る")
    func undoRestoresGroupCrossPackMove() throws {
        let fx = try makeFixture()
        let (packA, packB, g1, _, _, _) = seedTwoPacks(in: fx.context)

        // 初期状態：g1 は packA の子
        #expect(g1.parent?.id == "PA")
        #expect(packA.child.contains { $0.id == "G1" })
        #expect(packB.child.contains { $0.id == "G1" } == false)

        // Pack A の G1 を Pack B に移動
        fx.service.perform(context: fx.context) {
            g1.parent = packB
        }
        // 移動後の状態確認
        let movedGroup = try fx.context.fetch(FetchDescriptor<M2Group>()).first { $0.id == "G1" }
        #expect(movedGroup?.parent?.id == "PB")

        // Undo で元に戻る
        fx.service.undo(context: fx.context)

        // === Fix 8 検証ポイント ===
        // 旧版は restore() が pack.child のローカル辞書を使っていたため、
        // G1 が PB 配下にいると Pack A の復元時に新規 Group を作ろうとして
        // @Attribute(.unique) 制約違反を起こしていた。
        // 新版はグローバル辞書から G1 を見つけて Pack A に re-parent する。
        let restoredGroup = try fx.context.fetch(FetchDescriptor<M2Group>()).first { $0.id == "G1" }
        #expect(restoredGroup?.parent?.id == "PA",
                "Undo 後の G1 の親が PA ではない: \(restoredGroup?.parent?.id ?? "nil")")
    }

    @Test("Item の Group 越境（同一 Pack 内）を Undo すると元の Group に戻る")
    func undoRestoresItemCrossGroupMoveWithinPack() throws {
        let fx = try makeFixture()
        // g1 はテスト中に直接参照しないが、ID で id="G1" の Group を後段で fetch して扱う
        let (packA, _, _, _, i1, _) = seedTwoPacks(in: fx.context)

        // Pack A に新しい Group g3 を作って、そこに i1 を移動する
        let g3 = M2Group(id: "G3", name: "G3", order: ORDER_SPARSE, parent: packA)
        fx.context.insert(g3)
        // ここまでは Undo 対象にしない（初期状態の拡張として扱う）

        // i1 を g1 から g3 へ移動
        fx.service.perform(context: fx.context) {
            i1.parent = g3
        }

        let movedItem = try fx.context.fetch(FetchDescriptor<M3Item>()).first { $0.id == "I1" }
        #expect(movedItem?.parent?.id == "G3")

        // Undo
        fx.service.undo(context: fx.context)

        let restoredItem = try fx.context.fetch(FetchDescriptor<M3Item>()).first { $0.id == "I1" }
        #expect(restoredItem?.parent?.id == "G1",
                "Undo 後の I1 の親が G1 ではない: \(restoredItem?.parent?.id ?? "nil")")
        // 兄弟確認
        let restoredGroup = try fx.context.fetch(FetchDescriptor<M2Group>()).first { $0.id == "G1" }
        let itemIds = restoredGroup?.child.map(\.id).sorted() ?? []
        #expect(itemIds == ["I1", "I2"])
    }

    @Test("Item の Pack 越境（A の G1 から B の G2 へ）を Undo で元に戻せる")
    func undoRestoresItemCrossPackMove() throws {
        let fx = try makeFixture()
        let (_, _, _, g2, i1, _) = seedTwoPacks(in: fx.context)

        // i1 を Pack A の G1 から Pack B の G2 へ移動
        fx.service.perform(context: fx.context) {
            i1.parent = g2
        }

        let movedItem = try fx.context.fetch(FetchDescriptor<M3Item>()).first { $0.id == "I1" }
        #expect(movedItem?.parent?.id == "G2")
        #expect(movedItem?.parent?.parent?.id == "PB")

        // Undo
        fx.service.undo(context: fx.context)

        let restoredItem = try fx.context.fetch(FetchDescriptor<M3Item>()).first { $0.id == "I1" }
        #expect(restoredItem?.parent?.id == "G1")
        #expect(restoredItem?.parent?.parent?.id == "PA")
    }

    // MARK: - Fix 10: transactionDepth の不変条件

    @Test("対応しない commitTransaction は安全に吸収される（depth は負にならない）")
    func unbalancedCommitDoesNotCrashOrCorrupt() throws {
        let fx = try makeFixture()
        _ = seedTwoPacks(in: fx.context)

        // begin なしで commit を 3 回呼んでも canUndo が変化しない
        fx.service.commitTransaction(context: fx.context)
        fx.service.commitTransaction(context: fx.context)
        fx.service.commitTransaction(context: fx.context)

        #expect(fx.service.canUndo == false)
        #expect(fx.service.canRedo == false)

        // その後の正常な perform はちゃんと動く（Fix 10 で内部状態がクリーンに保たれる）
        let (packA, _, _, _, _, _) = seedTwoPacks(in: fx.context)
        fx.service.perform(context: fx.context) {
            packA.name = "AfterUnbalanced"
        }
        #expect(fx.service.canUndo == true)
    }

    @Test("Undo を実行した直後にも transactionDepth が破綻せず次の編集が記録される")
    func transactionStateRecoversAfterRestore() throws {
        let fx = try makeFixture()
        let (packA, _, _, _, _, _) = seedTwoPacks(in: fx.context)

        // 1回目の編集
        fx.service.perform(context: fx.context) {
            packA.name = "Edit1"
        }
        // Undo（restore() 内部で transactionDepth がリセットされる）
        fx.service.undo(context: fx.context)
        // restore 後に 2回目の編集ができることを検証
        fx.service.perform(context: fx.context) {
            packA.name = "Edit2"
        }

        // 直近のスナップショットが Edit2 として記録されている
        // canUndo は true（Edit2 を Undo できる）、canRedo は false（新規操作で消失）
        #expect(fx.service.canUndo == true)
        #expect(fx.service.canRedo == false)

        fx.service.undo(context: fx.context)
        let undone = try fx.context.fetch(FetchDescriptor<M1Pack>()).first { $0.id == "PA" }
        // Edit2 を Undo した結果は「Edit1 を Undo した直後の状態」= 初期値
        #expect(undone?.name == "PackA")
    }

    // MARK: - 履歴上限

    @Test("maxStackSize を超える操作で古い履歴は捨てられる")
    func undoStackRespectsMaxSize() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: M1Pack.self, M2Group.self, M3Item.self, configurations: configuration)
        let context = container.mainContext
        let service = UndoStackService(maxStackSize: 3)

        let pack = M1Pack(id: "P", name: "P0", order: 0)
        context.insert(pack)

        // 5回編集（上限 3 を超える）
        for i in 1...5 {
            service.perform(context: context) {
                pack.name = "P\(i)"
            }
        }

        // 5回 Undo しても 3回しか戻れない
        for _ in 0..<5 {
            service.undo(context: context)
        }

        let restored = try context.fetch(FetchDescriptor<M1Pack>()).first { $0.id == "P" }
        // 3回しか戻らないので、P5 → P4 → P3 → P2 の順に戻り P2 で止まる
        #expect(restored?.name == "P2")
    }
}
