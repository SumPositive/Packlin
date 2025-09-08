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
    @State private var expandedPack: M1Pack?

    var body: some View {
        NavigationView {
            List {
                if let expanded = expandedPack {
                    Section {
                        ForEach(sortedGroups(of: expanded)) { group in
                            GroupRowView(group: group)
                        }
                        .onMove { indices, newOffset in
                            moveGroup(in: expanded, from: indices, to: newOffset)
                        }
                        .environment(\.editMode, .constant(.active))
                    } header: {
                        PackRowView(
                            pack: expanded,
                            isExpanded: true,
                            onExpand: { expandedPack = expanded },
                            onCollapse: { expandedPack = nil }
                        )
                    }
                }

                ForEach(packs.filter { $0.id != expandedPack?.id }) { pack in
                    PackRowView(
                        pack: pack,
                        isExpanded: false,
                        onExpand: { expandedPack = pack },
                        onCollapse: { expandedPack = nil }
                    )
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

    private func sortedGroups(of pack: M1Pack) -> [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }

    private func moveGroup(in pack: M1Pack, from source: IndexSet, to destination: Int) {
        var groups = sortedGroups(of: pack)
        groups.move(fromOffsets: source, toOffset: destination)
        for (index, group) in groups.enumerated() {
            group.order = index
        }
        pack.child = groups
    }
}

#Preview {
    ContentView()
}
