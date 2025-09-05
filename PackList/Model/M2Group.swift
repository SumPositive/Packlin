import Foundation
import SwiftData

@Model
final class M2Group {  // "Group"ではSwiftUI.Groupと競合するため"M2"を付与することになった。"M"はModel
    var name: String
    var note: String
    @Relationship(inverse: \M1Title.child) var parent: M1Title?
    @Relationship(deleteRule: .cascade) var child: [M3Item] = []

    init(name: String, note: String = "", parent: M1Title? = nil) {
        self.name = name
        self.note = note
        self.parent = parent
    }
}
