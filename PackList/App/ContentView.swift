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
    @Query(sort: [SortDescriptor(\M1Pack.createdAt, order: .reverse)]) private var packs: [M1Pack]
    @State private var lastAddedPackID: M1Pack.ID?
    @State private var draggingItem: M3Item?
    private let rowHeight: CGFloat = 44

    var body: some View {
        NavigationView {
            List {
                ForEach(packs) { pack in
                    PackRowView(pack: pack,
                                isNew: pack.id == lastAddedPackID,
                                lastAddedPackID: $lastAddedPackID,
                                draggingItem: $draggingItem)
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
        let newPack = M1Pack(name: "")
        modelContext.insert(newPack)
        lastAddedPackID = newPack.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            lastAddedPackID = nil
        }
    }
}

#Preview {
    ContentView()
}
