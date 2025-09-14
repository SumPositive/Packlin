import Foundation

extension Notification.Name {
    static let undoManagerWillCloseGroup = Notification.Name("NSUndoManagerWillCloseUndoGroup")
    static let undoManagerDidUndo = Notification.Name("NSUndoManagerDidUndoChange")
    static let undoManagerDidRedo = Notification.Name("NSUndoManagerDidRedoChange")
}

