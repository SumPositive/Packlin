import Foundation
import SwiftData

@Model
final class E2Group {
    var name: String
    var note: String
    @Relationship(inverse: \E1Title.child) var parent: E1Title?
    @Relationship(deleteRule: .cascade) var child: [E3Item] = []

    init(name: String, note: String = "", parent: E1Title? = nil) {
        self.name = name
        self.note = note
        self.parent = parent
    }
}
