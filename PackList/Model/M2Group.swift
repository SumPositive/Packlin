import Foundation
import SwiftData

@Model
final class M2Group {  // "Group"ではSwiftUI.Groupと競合するため"M2"を付与することになった。"M"はModel
    var name: String
    var note: String
    @Relationship(inverse: \M1Title.child) var parent: M1Title?
    @Relationship(deleteRule: .cascade) var child: [M3Item] = []

    var stockWeight: Int { child.reduce(0) { $0 + $1.weight * $1.stock } }
    var needWeight: Int { child.reduce(0) { $0 + $1.weight * $1.need } }

    init(name: String, note: String = "", parent: M1Title? = nil) {
        self.name = name
        self.note = note
        self.parent = parent
    }
}
