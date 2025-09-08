//
//  ContentView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]
    private let rowHeight: CGFloat = 44

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(packs) { pack in
                        PackRowView(pack: pack)
                    }
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { }
                    label: {
                        Image(systemName: "info.circle")
                    }
                    .padding(.leading, 8)

                    Button {
                    } label: {
                        Button {
                            // UnDo
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                    .padding(.leading, 20)
                    
                    Spacer()
                    Text("モチメモ")
                    Spacer()

                    Button {
                    } label: {
                        Button {
                            // ReDo
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                        }
                    }
                    .padding(.trailing, 20)

                    Button { addPack() }
                    label: {
                        Image(systemName: "plus.message")
                    }
                    .padding(.trailing, 8)
                }
                .frame(height: rowHeight)
                .padding(.horizontal)
                .background(.thinMaterial)
            }
        }
    }

    private func addPack() {
        let newPack = M1Pack(name: "", order: M1Pack.nextPackOrder(packs))
        modelContext.insert(newPack)
    }

    private func movePack(from source: IndexSet, to destination: Int) {
        var items = packs
        items.move(fromOffsets: source, toOffset: destination)
        for (index, pack) in items.enumerated() {
            pack.order = index
        }
    }
}

#Preview {
    ContentView()
}
