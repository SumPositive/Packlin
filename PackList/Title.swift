import Foundation
import SwiftData

@Model
final class Title {
    var name: String
    var note: String
    @Relationship(deleteRule: .cascade) var child: [Group] = []

    init(name: String, note: String = "") {
        self.name = name
        self.note = note
    }
}
