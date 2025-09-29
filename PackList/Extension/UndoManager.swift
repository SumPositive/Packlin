//
//  UndoManager.swift
//  PackList
//
//  Created by sumpo on 2025/09/29.
//

import Foundation
import ObjectiveC.runtime
import SwiftUI

/// 自動イベントグルーピングを無効化した上で、独自にグルーピングするための拡張
/// 　undoManager.groupsByEvent = false になっていること、
/// 　さもなくばcloseAllUndoGroupsでオーバーEndで 落ちる
public extension UndoManager {

    private struct AssociatedKeys {
        static var manualGroupingCount = "manualGroupingCount"
    }

    private var manualGroupingCount: Int {
        get {
            (objc_getAssociatedObject(self, &AssociatedKeys.manualGroupingCount) as? NSNumber)?.intValue ?? 0
        }
        set {
            let value = max(newValue, 0)
            objc_setAssociatedObject(self,
                                     &AssociatedKeys.manualGroupingCount,
                                     NSNumber(value: value),
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Undo grouping BEGIN
    func groupingBegin() {
        manualGroupingCount += 1
        beginUndoGrouping()
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// Undo grouping END
    func groupingEnd() {
        guard manualGroupingCount > 0 else {
            // 各画面にあるUndo/Redoアイコンを更新する
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            return
        }
        manualGroupingCount -= 1
        if 0 < groupingLevel {
            endUndoGrouping()
        }
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// 全てのグルーピングを閉じる
    func closeAllUndoGroups() {
        guard manualGroupingCount > 0 else { return }
        while 0 < groupingLevel && manualGroupingCount > 0 {
            manualGroupingCount -= 1
            endUndoGrouping()
        }
        manualGroupingCount = 0
    }

    /// Undo
    func performUndo() {
        // 全てのグルーピングを閉じる（閉じずにUndoするとクラッシュ）
        closeAllUndoGroups()
        manualGroupingCount = 0
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
        manualGroupingCount = 0
        withAnimation {
            redo()
        }
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }
    
}
