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

    /// 独自グルーピングを開始した時点のgroupingLevelを積み上げるスタック
    /// 　SwiftData内部でネストされたUndoグループが追加されるケースがあるため、
    /// 　終了時は「開始時のレベルまで確実に戻す」必要がある。
    private struct AssociatedKeys {
        static var manualGroupingStack: UInt8 = 0
    }
    /// 　extensionでは単純なインスタンス変数を保持できないため、Objective-Cランタイムを利用して配列を保持する
    private var manualGroupingStack: [Int] {
        get {
            (objc_getAssociatedObject(self, &AssociatedKeys.manualGroupingStack) as? [Int]) ?? []
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
        // 現在のgroupingLevelをスタックに積む（これ以降にネストが増えても終了時に巻き戻せる）
        var stack = manualGroupingStack
        stack.append(groupingLevel)
        manualGroupingStack = stack
        beginUndoGrouping()
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// Undo grouping END
    func groupingEnd() {
        // スタックから開始時のgroupingLevelを取り出す。無ければ独自Beginは未実行。
        var stack = manualGroupingStack
        guard let baselineLevel = stack.popLast() else {
            // 各画面にあるUndo/Redoアイコンを更新する
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            return
        }
        manualGroupingStack = stack
        // Begin時点までgroupingLevelを巻き戻す。SwiftData側でネストされたグループが生成される場合があるため、
        // whileループで安全に閉じていく。
        closeUndoGroups(until: baselineLevel)
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// 全てのグルーピングを閉じる
    func closeAllUndoGroups() {
        // スタックに積まれている分だけ順番に巻き戻す
        var stack = manualGroupingStack
        while let baselineLevel = stack.popLast() {
            closeUndoGroups(until: baselineLevel)
        }
        manualGroupingStack = []
        // 念のため、内部に残ってしまったグループがあればすべて閉じて整合性を保つ
        closeUndoGroups(until: 0)
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
    /// groupingLevel が targetLevel 以下になるまで endUndoGrouping() を繰り返す
    /// 　targetLevel は groupingBegin() 呼び出し前の状態を示す。
    func closeUndoGroups(until targetLevel: Int) {
        guard groupingLevel > targetLevel else {
            return
        }
        var previousLevel = groupingLevel
        while groupingLevel > targetLevel {
            endUndoGrouping()
            // 想定外の理由でlevelが変化しない場合は無限ループを避ける
            if groupingLevel == previousLevel {
                break
            }
            previousLevel = groupingLevel
        }
    }
}
