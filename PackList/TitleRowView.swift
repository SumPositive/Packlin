import SwiftUI
import SwiftData
import UIKit

struct TitleRowView: View {
    @Environment(\.modelContext) private var modelContext
    let title: M1Title
    @State private var isExpanded = false
    @State private var editingTitle: M1Title?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
    private let rowHeight: CGFloat = 44

    var body: some View {
        Group {
            HStack {
                Button {
                    isExpanded.toggle()
                    if isExpanded && title.child.isEmpty {
                        addGroup()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(BorderlessButtonStyle())
                Image(systemName: "bag")
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.name.isEmpty ? "New Title" : title.name)
                        .foregroundStyle(title.name.isEmpty ? .secondary : .primary)
                    Text("在庫重量:\(title.stockWeight)g　必要重量:\(title.needWeight)g")
                        .font(.caption2)
                }
                Spacer()
                Button { addGroup() } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .frame(height: rowHeight)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleteTitle() } label: {
                    Image(systemName: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { copyTitle() } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
            .contentShape(Rectangle())
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { frame = $0 }
                }
            )
            .onTapGesture {
                arrowEdge = arrowEdge(for: frame)
                editingTitle = title
            }
            .popover(item: $editingTitle, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { title in
                EditTitleView(title: title)
                    .presentationCompactAdaptation(.none)
            }

            if isExpanded {
                ForEach(title.child) { group in
                    GroupRowView(group: group)
                }
            }
        }
    }

    private func addGroup() {
        let newGroup = M2Group(name: "", parent: title)
        modelContext.insert(newGroup)
    }

    private func deleteTitle() {
        for group in title.child {
            deleteGroup(group)
        }
        modelContext.delete(title)
    }

    private func deleteGroup(_ group: M2Group) {
        for item in group.child {
            modelContext.delete(item)
        }
        modelContext.delete(group)
    }

    private func copyTitle() {
        let newTitle = M1Title(name: title.name, note: title.note, createdAt: title.createdAt.addingTimeInterval(-0.001))
        modelContext.insert(newTitle)
        for group in title.child {
            copyGroup(group, to: newTitle)
        }
    }

    private func copyGroup(_ group: M2Group, to parent: M1Title) {
        let newGroup = M2Group(name: group.name, note: group.note, parent: parent)
        modelContext.insert(newGroup)
        if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
            parent.child.insert(newGroup, at: index + 1)
        } else {
            parent.child.append(newGroup)
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
    }

    private func copyItem(_ item: M3Item, to parent: M2Group) {
        let newItem = M3Item(name: item.name, note: item.note, stock: item.stock, need: item.need, weight: item.weight, parent: parent)
        modelContext.insert(newItem)
        if let index = parent.child.firstIndex(where: { $0.id == item.id }) {
            parent.child.insert(newItem, at: index + 1)
        } else {
            parent.child.append(newItem)
        }
    }

    private func arrowEdge(for frame: CGRect?) -> Edge {
        guard let frame = frame else { return .bottom }
        let screenHeight = UIScreen.main.bounds.height
        let topSpace = frame.minY
        let bottomSpace = screenHeight - frame.maxY
        return bottomSpace > topSpace ? .top : .bottom
    }
}

struct EditTitleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var title: M1Title
    
    var body: some View {
        VStack {
            TextField("", text: $title.name, prompt: Text("New Title"))
            TextField("Note", text: $title.note)
            HStack {
                Spacer()
                Button("Done") {
                    try? context.save()
                    dismiss()
                }
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

