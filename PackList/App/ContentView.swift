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
                        modelContext.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!(modelContext.undoManager?.canUndo ?? false))
                    .padding(.horizontal, 15)

                    Button {
                        modelContext.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!(modelContext.undoManager?.canRedo ?? false))
                    .padding(.horizontal, 15)

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
