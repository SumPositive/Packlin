import Foundation
import SwiftUI

public extension UndoManager {
    func closeAllUndoGroups() {
        while groupingLevel > 0 {
            endUndoGrouping()
        }
    }

    func performUndo(updateState: () -> Void = {}) {
        closeAllUndoGroups()
        withAnimation {
            undo()
        }
        updateState()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    func performRedo(updateState: () -> Void = {}) {
        closeAllUndoGroups()
        withAnimation {
            redo()
        }
        updateState()
        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }
}
