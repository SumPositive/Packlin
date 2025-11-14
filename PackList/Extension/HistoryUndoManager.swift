import Foundation
import SwiftData

final class HistoryUndoManager: UndoManager {
    // SwiftData の ModelContext と履歴サービスを橋渡しするためのクラス
    private unowned let context: ModelContext
    weak var history: HistoryService?

    init(context: ModelContext, history: HistoryService) {
        self.context = context
        self.history = history
        super.init()
    }

    override func beginUndoGrouping() {
        guard let history else { return }
        // begin が呼ばれたタイミングでスナップショットを保存する
        history.beginTransaction(context: context)
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    override func endUndoGrouping() {
        guard let history else { return }
        // end では差分があれば履歴スタックへ積む
        history.commitTransaction(context: context)
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    override var canUndo: Bool {
        history?.canUndo ?? false
    }

    override func undo() {
        guard let history else { return }
        // Undo 実行後にUIを更新するため通知を送る
        history.undo(context: context)
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    override var canRedo: Bool {
        history?.canRedo ?? false
    }

    override func redo() {
        guard let history else { return }
        // Redo も同様に履歴サービスへ委譲する
        history.redo(context: context)
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    override func removeAllActions() {
        // SwiftUIの各画面と連携してボタン状態をリセットする
        history?.reset()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }
}

public extension UndoManager {
    func groupingBegin() {
        // 既存コードの呼び出し元を変えずに履歴サービスへ橋渡しする
        beginUndoGrouping()
    }

    func groupingEnd() {
        endUndoGrouping()
    }

    func closeAllUndoGroups() {}

    func performUndo() {
        // optional chaining から呼び出されるため安全側でメソッドを用意する
        undo()
    }

    func performRedo() {
        redo()
    }
}
