//
//  UndoManager.swift
//  PackList
//
//  Created by sumpo on 2025/09/29.
//

import Foundation
import ObjectiveC.runtime
import SwiftUI

/// 独自にグルーピング制御するための拡張
/// 　自動イベントグルーピング有効：undoManager.groupsByEvent = false (default)
public extension UndoManager {

    /// Objective-Cランタイムにぶら下げるAssociatedObjectのキー
    private struct AssociatedKeys {
        static var manualGroupingStack: UInt8 = 0
    }

    /// groupingBegin() 呼び出し時に記録するスナップショット
    private struct ManualGroupingSnapshot {
        /// Begin前に存在していたgroupingLevel（外側の状態）
        let baselineLevel: Int
        /// beginUndoGrouping() を実行した直後のgroupingLevel（独自グループ自身の高さ）
        let manualLevel: Int
    }

    /// 　extensionでは単純なインスタンス変数を保持できないため、Objective-Cランタイムを利用して配列を保持する
    private var manualGroupingStack: [ManualGroupingSnapshot] {
        get {
            (objc_getAssociatedObject(self, &AssociatedKeys.manualGroupingStack) as? [ManualGroupingSnapshot]) ?? []
        }
        set {
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.manualGroupingStack,
                                     newValue,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Undo grouping BEGIN
    func groupingBegin() {
        // Begin前のgroupingLevelを記録しておき、後で安全に巻き戻せるようにする
        let baselineLevel = groupingLevel
        beginUndoGrouping()
        // Begin直後のgroupingLevelを含むスナップショットを積む
        var stack = manualGroupingStack
        stack.append(ManualGroupingSnapshot(baselineLevel: baselineLevel,
                                            manualLevel: groupingLevel))
        manualGroupingStack = stack
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// Undo grouping END
    func groupingEnd() {
        // 記録済みのスナップショットが無ければ独自Beginは未実行とみなす
        var stack = manualGroupingStack
        guard let snapshot = stack.popLast() else {
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            return
        }
        manualGroupingStack = stack
        // SwiftDataが内部で積んだネストを手動グループの高さまで縮退させる
        let nestedClosed = closeNestedUndoGroups(downTo: snapshot.manualLevel)
        if nestedClosed {
            // ネストが正常に閉じられたら独自グループ本体を閉じる
            let manualClosed = closeManualUndoGroup(using: snapshot)
            if manualClosed == false {
                // 万一閉じ切れなかった場合は安全のため全体リセットを試みる
                closeResidualUndoGroups()
            }
        } else {
            // ネストが閉じられなかった場合も全体リセットで整合性を図る
            closeResidualUndoGroups()
        }
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// 全てのグルーピングを閉じる
    func closeAllUndoGroups() {
        // 内側から順番に独自グループを閉じていく
        var stack = manualGroupingStack
        while let snapshot = stack.popLast() {
            let nestedClosed = closeNestedUndoGroups(downTo: snapshot.manualLevel)
            let manualClosed = nestedClosed ? closeManualUndoGroup(using: snapshot) : false
            if manualClosed == false {
                // どこかで閉じ損ねた場合は残存グループをまとめて整理する
                closeResidualUndoGroups()
                break
            }
        }
        manualGroupingStack = []
        // 念のため未知のグループが残っていれば追加で整理する
        closeResidualUndoGroups()
    }

    /// Undo
    func performUndo() {
        // 全てのグルーピングを閉じる（閉じずにUndoするとクラッシュ）
        closeAllUndoGroups()
        withAnimation {
            undo()
        }
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// Redo
    func performRedo() {
        // Redoが不可能な状態でredo()を呼ぶとSwiftData側で不整合が起きるため、ここで早期リターンする
        guard canRedo else {
            // UI表示が正しく更新されるよう通知だけは発行しておく
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            return
        }
        // 全てのグルーピングを閉じる（閉じずにRedoするとクラッシュ）
        closeAllUndoGroups()
        withAnimation {
            redo()
        }
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }
}

private extension UndoManager {

    /// SwiftDataなどが内部で生成したネストを指定レベル以下まで縮退させる
    /// - Parameter manualLevel: 独自グループ直後の高さ
    /// - Returns: 指定レベル以下まで正常に縮退できた場合はtrue
    @discardableResult
    func closeNestedUndoGroups(downTo manualLevel: Int) -> Bool {
        guard manualLevel < groupingLevel else {
            return true
        }
        var previousLevel = groupingLevel
        var safetyCounter = 0
        while manualLevel < groupingLevel {
            endUndoGrouping()
            if groupingLevel <= manualLevel {
                return true
            }
            if groupingLevel < previousLevel {
                previousLevel = groupingLevel
                safetyCounter += 1
                if 32 <= safetyCounter {
                    // 過剰なネストが検出された場合は安全側で終了する
                    break
                }
                continue
            }
            // groupingLevelが変化しない場合は無限ループを避ける
            break
        }
        return groupingLevel <= manualLevel
    }

    /// 独自に開始したグループ本体を閉じる
    /// - Parameter snapshot: groupingBegin() 時に記録した情報
    /// - Returns: 正常に閉じられた場合はtrue
    @discardableResult
    func closeManualUndoGroup(using snapshot: UndoManager.ManualGroupingSnapshot) -> Bool {
        guard snapshot.manualLevel <= groupingLevel else {
            // 既に閉じられているとみなし成功扱いにする
            return true
        }
        let previousLevel = groupingLevel
        endUndoGrouping()
        if groupingLevel < previousLevel {
            // Baselineより高い場合は想定外のネストが残っているため追加で縮退を試みる
            if snapshot.baselineLevel < groupingLevel {
                let adjusted = closeNestedUndoGroups(downTo: snapshot.baselineLevel)
                return adjusted
            }
            return groupingLevel <= snapshot.baselineLevel
        }
        return false
    }

    /// 残余のグルーピングがあれば安全な範囲で閉じる
    func closeResidualUndoGroups() {
        var previousLevel = groupingLevel
        var safetyCounter = 0
        while 0 < groupingLevel {
            endUndoGrouping()
            if groupingLevel < previousLevel {
                previousLevel = groupingLevel
                safetyCounter += 1
                if 32 <= safetyCounter {
                    break
                }
                continue
            }
            break
        }
    }
}
