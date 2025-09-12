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
                    ZStack(alignment: .leading) {
                        PackRowView(pack: pack)

                        GeometryReader { proxy in
                            HStack(spacing: 0) {
                                Color.clear
                                    .frame(width: proxy.size.width / 2)
                                    .allowsHitTesting(false)

                                NavigationLink(destination: GroupListView(pack: pack)) {
                                    Color.clear
                                        .frame(width: proxy.size.width / 2)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .onMove(perform: movePack)
                .environment(\.editMode, .constant(.active))
            }
            .listStyle(.plain)
            .padding(.top, -8) // headerとPackList間の余白を無くす
            .padding(.horizontal, 8)
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { }
                    label: {
                        Image(systemName: "info.circle")
                    }

                    Button {
                        // UnDo
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(true)
                    .padding(.horizontal, 30)
                    
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
