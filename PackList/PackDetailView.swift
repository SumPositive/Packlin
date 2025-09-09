//
//  PackDetailView.swift
//  PackList
//
//  Created by ChatGPT on 2025/09/09.
//

import SwiftUI
import SwiftData

struct PackDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let pack: M1Pack

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            if let firstGroup = sortedGroups.first {
                Section {
                    // コンテンツは不要。GroupRowView をセクションヘッダーとして表示する
                } header: {
                    GroupRowView(group: firstGroup)
                }
            }

            ForEach(sortedGroups.dropFirst()) { group in
                GroupRowView(group: group)
            }
            .onMove(perform: moveGroup)
            .environment(\.editMode, .constant(.active))
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .navigationTitle(pack.name.isEmpty ? "New Pack" : pack.name)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack {
                    Button {
                        // ＜ 戻る
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    
                    Button {
                        // UnDo
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(true)
                    .padding(.horizontal, 30)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addGroup()
                } label: {
                    Image(systemName: "plus.rectangle")
                }
            }
        }
    }

    private func addGroup() {
        let newGroup = M2Group(name: "", order: pack.nextGroupOrder(), parent: pack)
        modelContext.insert(newGroup)
        withAnimation {
            pack.child.append(newGroup)
            pack.normalizeGroupOrder()
        }
    }

    private func moveGroup(from source: IndexSet, to destination: Int) {
        // 先頭のグループはピン留めされているため、残りのグループのみを並べ替える
        guard !sortedGroups.isEmpty else { return }

        var remaining = Array(sortedGroups.dropFirst())
        remaining.move(fromOffsets: source, toOffset: destination)

        // 新しい順序を適用（0 はピン留めされたグループ）
        var reordered: [M2Group] = [sortedGroups[0]]
        for (index, group) in remaining.enumerated() {
            group.order = index + 1
            reordered.append(group)
        }
        pack.child = reordered
    }
}

