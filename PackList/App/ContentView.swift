import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\M1Title.createdAt, order: .reverse)]) private var titles: [M1Title]
    @State private var lastAddedTitleID: M1Title.ID?
    private let rowHeight: CGFloat = 44

    var body: some View {
        NavigationView {
            List {
                ForEach(titles) { title in
                    TitleRowView(title: title, isNew: title.id == lastAddedTitleID, lastAddedTitleID: $lastAddedTitleID)
                }
            }
            .listStyle(.plain)
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { }
                    label: {
                        Image(systemName: "info.circle")
                    }
                    Spacer()
                    Text("モチメモ")
                    Spacer()
                    Button { addTitle() }
                    label: {
                        Image(systemName: "bag.badge.plus")
                    }
                }
                .frame(height: rowHeight)
                .padding(.horizontal)
                .background(.thinMaterial)
            }
        }
    }

    private func addTitle() {
        let newTitle = M1Title(name: "")
        modelContext.insert(newTitle)
        lastAddedTitleID = newTitle.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedTitleID = nil
        }
    }
}

#Preview {
    ContentView()
}
