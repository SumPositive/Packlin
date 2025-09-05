import SwiftUI
import SwiftData

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

struct EditGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var group: M2Group

    var body: some View {
        VStack {
            TextField("", text: $group.name, prompt: Text("New Group"))
            TextField("Note", text: $group.note)
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
