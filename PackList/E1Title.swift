import Foundation
import SwiftData

@Model
final class E1Title {
    var name: String
    var note: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var child: [E2Group] = []

    init(name: String, note: String = "", createdAt: Date = Date()) {
        self.name = name
        self.note = note
        self.createdAt = createdAt
    }
}
