import SwiftUI
import SwiftData

struct TitleList: View {
    let titles: [Title]
    @State private var expandedTitles: Set<PersistentIdentifier> = []
    @State private var editingTitle: Title?

    var body: some View {
        Group {
            ForEach(titles) { title in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedTitles.contains(title.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedTitles.insert(title.id)
                            } else {
                                expandedTitles.remove(title.id)
                            }
                        }
                    )
                ) {
                    GroupList(groups: title.child)
                } label: {
                    HStack {
                        Text(title.name)
                        Spacer()
                        Button {
                            editingTitle = title
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
        }
        .sheet(item: $editingTitle) { title in
            EditTitleView(title: title)
        }
    }
}

