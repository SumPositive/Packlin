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

    /// 独自グルーピング・カウンタ
    ///　　自動イベントグルーピングに干渉しないように独自にカウントする必要がある
    private struct AssociatedKeys {
        static var manualGroupingCount: UInt8 = 0
    }
    /// 　extensionでは、単純なインスタンス変数として保持できないため、
    /// 　Objective-C の objc_getAssociatedObject を利用して保持させる
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
        // 独自グルーピング・カウンタ+1
        manualGroupingCount += 1
        beginUndoGrouping()
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// Undo grouping END
    func groupingEnd() {
        guard 0 < manualGroupingCount else {
            // groupingLevelに残りがある場合、それは自動イベントグルーピングであるから閉じない
            // 各画面にあるUndo/Redoアイコンを更新する
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
            return
        }
        // 独自グルーピング・カウンタ-1
        manualGroupingCount -= 1
        // End
        if 0 < groupingLevel {
            // 独自グルーピングだけを閉じる
            endUndoGrouping()
        }
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// 全てのグルーピングを閉じる
    func closeAllUndoGroups() {
        guard 0 < manualGroupingCount else {
            // 独自グルーピング・カウ・クリア
            manualGroupingCount = 0
            // groupingLevelに残りがある場合、それは自動イベントグルーピングであるから閉じない
            return
        }
        while 0 < groupingLevel && 0 < manualGroupingCount {
            // 独自グルーピング・カウンタ-1
            manualGroupingCount -= 1
            // 独自グルーピングだけを閉じる
            endUndoGrouping()
        }
        // 独自グルーピング・カウ・クリア
        manualGroupingCount = 0
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
