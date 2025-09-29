//
//  UndoManager.swift
//  PackList
//
//  Created by sumpo on 2025/09/29.
//

import Foundation
import SwiftUI

/// 自動イベントグルーピングを無効化した上で、独自にグルーピングするための拡張
/// 　undoManager.groupsByEvent = false になっていること、
/// 　さもなくばcloseAllUndoGroupsでオーバーEndで 落ちる
public extension UndoManager {

    /// Undo grouping BEGIN
    func groupingBegin() {
        beginUndoGrouping()
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }
    
    /// Undo grouping END
    func groupingEnd() {
        if 0 < groupingLevel {
            endUndoGrouping()
        }
        // 各画面にあるUndo/Redoアイコンを更新する
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    /// 全てのグルーピングを閉じる
    func closeAllUndoGroups() {
        while 0 < groupingLevel {
            endUndoGrouping()
        }
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
