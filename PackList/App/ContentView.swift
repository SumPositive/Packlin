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
    @State private var canUndo = false
    @State private var canRedo = false

    var body: some View {
        NavigationView {
            List {
                ForEach(packs) { pack in
                    ZStack {
                        PackRowView(pack: pack)

                        HStack(spacing: 0) {
                            Spacer()
                            NavigationLink(destination: GroupListView(pack: pack)) {
                                Color.clear
                            }
                            .frame(width: 80)
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .background(Color.clear).contentShape(Rectangle()) //タップ領域
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .onMove(perform: movePack)
                .environment(\.editMode, .constant(.active))
            }
            .listStyle(.plain)
            .padding(.top, -8) // headerとPackList間の余白を無くす
            .padding(.horizontal, 0)
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { } 
                    label: {
                        Image(systemName: "info.circle")
                    }

                    Button {
                        modelContext.undoManager?.undo()
                        updateUndoRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo)
                    .padding(.horizontal, 15)

                    Button {
                        modelContext.undoManager?.redo()
                        updateUndoRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo)
                    .padding(.trailing, 15)
                    
                    Spacer()
                    Text("モチメモ")
                    Spacer()

                    Button {
                        // Setting
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .padding(.horizontal, 30)

                    Button { addPack() }
                    label: {
                        Image(systemName: "plus.message")
                    }
                }
                .frame(height: rowHeight)
                .padding(.horizontal, 8)
                .background(.thinMaterial)
                .onAppear { updateUndoRedo() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
            updateUndoRedo()
        }
    }

    private func updateUndoRedo() {
        let manager = modelContext.undoManager
        canUndo = manager?.canUndo ?? false
        canRedo = manager?.canRedo ?? false
    }

    private func addPack() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        let newPack = M1Pack(name: "", order: M1Pack.nextPackOrder(packs))
        modelContext.insert(newPack)
    }

    private func movePack(from source: IndexSet, to destination: Int) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

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
