import Foundation
import SwiftData

@Model
final class Title {
    var name: String
    var note: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var child: [Group] = []

    init(name: String, note: String = "", createdAt: Date = Date()) {
        self.name = name
        self.note = note
        self.createdAt = createdAt
    }
}
