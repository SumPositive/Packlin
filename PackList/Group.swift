import Foundation
import SwiftData

@Model
final class Group {
    var name: String
    var note: String
    @Relationship(inverse: \Title.child) var parent: Title?
    @Relationship(deleteRule: .cascade) var child: [Item] = []

    init(name: String, note: String = "", parent: Title? = nil) {
        self.name = name
        self.note = note
        self.parent = parent
    }
}
