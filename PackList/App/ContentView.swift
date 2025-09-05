import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\M1Title.createdAt, order: .reverse)]) private var titles: [M1Title]
    private let rowHeight: CGFloat = 44

    var body: some View {
        NavigationView {
            List {
                ForEach(titles) { title in
                    TitleRowView(title: title)
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
    }
}

#Preview {
    ContentView()
}
