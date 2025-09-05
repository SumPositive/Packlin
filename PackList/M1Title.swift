import Foundation
import SwiftData

@Model
final class M1Title {
    var name: String
    var note: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var child: [M2Group] = []

    init(name: String, note: String = "", createdAt: Date = Date()) {
        self.name = name
        self.note = note
        self.createdAt = createdAt
    }
}
