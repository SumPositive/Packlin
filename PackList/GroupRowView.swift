import SwiftUI
import SwiftData
import UIKit

struct GroupRowView: View {
    @Environment(\.modelContext) private var modelContext
    let group: M2Group
    @State private var isExpanded = false
    @State private var editingGroup: M2Group?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
    private let rowHeight: CGFloat = 44

    var body: some View {
        Group {
            HStack {
                Button {
                    isExpanded.toggle()
                    if isExpanded && group.child.isEmpty {
                        addItem()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(BorderlessButtonStyle())
                Image(systemName: "folder")
                Text(group.name.isEmpty ? "New Group" : group.name)
                    .foregroundStyle(group.name.isEmpty ? .secondary : .primary)
                Spacer()
                Button { addItem() } label: {
                    Image(systemName: "plus.app")
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .frame(height: rowHeight)
            .padding(.leading)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleteGroup() } label: {
                    Image(systemName: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button { copyGroup() } label: {
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
                editingGroup = group
            }
            .popover(item: $editingGroup, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { group in
                EditGroupView(group: group)
                    .presentationCompactAdaptation(.none)
            }

            if isExpanded {
                if group.child.isEmpty {
                    Text(" ")
                        .padding(.leading, 40)
                } else {
                    ForEach(group.child) { item in
                        ItemRowView(item: item)
                    }
                }
            }
        }
    }

    private func addItem() {
        let newItem = M3Item(name: "", parent: group)
        modelContext.insert(newItem)
    }

    private func deleteGroup() {
        for item in group.child {
            modelContext.delete(item)
        }
        modelContext.delete(group)
    }

    private func copyGroup() {
        guard let parentTitle = group.parent else { return }
        let newGroup = M2Group(name: group.name, note: group.note, parent: parentTitle)
        modelContext.insert(newGroup)
        if let index = parentTitle.child.firstIndex(where: { $0.id == group.id }) {
            parentTitle.child.insert(newGroup, at: index + 1)
        } else {
            parentTitle.child.append(newGroup)
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
