import Foundation

extension UndoManager {
    func closeAllUndoGroups() {
        while groupingLevel > 0 {
            endUndoGrouping()
        }
    }

    func performUndo() {
        closeAllUndoGroups()

        guard canUndo else { return }

        undo()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    func performRedo() {
        closeAllUndoGroups()

        guard canRedo else { return }

        redo()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }
}
