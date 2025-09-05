import SwiftUI
import SwiftData

struct EditTitleView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var title: Title

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $title.name)
                TextField("Note", text: $title.note)
            }
            .navigationTitle("Edit Title")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

