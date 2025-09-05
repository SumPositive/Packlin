import SwiftUI
import SwiftData
import UIKit

struct ItemRowView: View {
    @Environment(\.modelContext) private var modelContext
    let item: M3Item
    @State private var editingItem: M3Item?
    @State private var frame: CGRect = .zero
    @State private var arrowEdge: Edge = .bottom
    private let rowHeight: CGFloat = 44

    var body: some View {
        HStack {
            Image(systemName: "app")
            Text(item.name.isEmpty ? "New Item" : item.name)
                .foregroundStyle(item.name.isEmpty ? .secondary : .primary)
            Spacer()
        }
        .frame(height: rowHeight)
        .padding(.leading, 40)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleteItem() } label: {
                Image(systemName: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { copyItem() } label: {
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
            editingItem = item
        }
        .popover(item: $editingItem, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) { item in
            EditItemView(item: item)
                .presentationCompactAdaptation(.none)
        }
    }

    private func deleteItem() {
        modelContext.delete(item)
    }

    private func copyItem() {
        guard let parent = item.parent else { return }
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


struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var item: M3Item
    
    var body: some View {
        VStack {
            TextField("", text: $item.name, prompt: Text("New Item"))
            TextField("Note", text: $item.note)
            Stepper("Stock: \(item.stock)", value: $item.stock)
            Stepper("Need: \(item.need)", value: $item.need)
            TextField("Weight", value: $item.weight, format: .number)
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

