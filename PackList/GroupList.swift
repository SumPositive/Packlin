import SwiftUI
import SwiftData

struct GroupList: View {
    let groups: [Group]
    @State private var expandedGroups: Set<PersistentIdentifier> = []

    var body: some View {
        ForEach(groups) { group in
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedGroups.contains(group.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedGroups.insert(group.id)
                        } else {
                            expandedGroups.remove(group.id)
                        }
                    }
                )
            ) {
                if group.child.isEmpty {
                    Text(" ")
                        .padding(.leading)
                } else {
                    ForEach(group.child) { item in
                        Text(item.name)
                            .padding(.leading)
                    }
                }
            } label: {
                HStack {
                    Text(group.name)
                    Spacer()
                }
            }
        }
    }
}

