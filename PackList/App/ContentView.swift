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
    @Environment(\.undoManager) private var undoManager
    @Query(sort: [SortDescriptor(\M1Pack.createdAt, order: .reverse)]) private var packs: [M1Pack]
    @State private var lastAddedPackID: M1Pack.ID?
    private let rowHeight: CGFloat = 44

    var body: some View {
        NavigationView {
            List {
                ForEach(packs) { pack in
                    PackRowView(pack: pack, isNew: pack.id == lastAddedPackID, lastAddedPackID: $lastAddedPackID)
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
                    if let undoManager, undoManager.canUndo {
                        Button { undoManager.undo() }
                        label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                    Spacer()
                    Text("モチメモ")
                    Spacer()
                    Button { addPack() }
                    label: {
                        Image(systemName: "plus.message")
                    }
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
