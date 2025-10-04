//
//  GroupListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//

import SwiftUI
import SwiftData

struct GroupListView: View {
    let pack: M1Pack

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingGroup: M2Group?
    @State private var popupAnchor: CGPoint?

    private let rowHeight: CGFloat = 44

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }
    
    // Popup表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingPopup: Bool { editingGroup != nil }

    
    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(sortedGroups) { group in
                        ZStack {
                            GroupRowView(group: group, isHeader: false) { selected, point in
                                editingGroup = selected
                                popupAnchor = point
                            }

                            GeometryReader { geo in
                                HStack {
                                    Spacer()
                                    NavigationLink(value: AppDestination.itemList(packID: pack.id, groupID: group.id)) {
                                        Color.clear
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        //.background(COLOR_ROW_GROUP)
                    }
                    .onMove(perform: moveGroup)
                }

                // 並べ替え一覧
                Section(header: Text("group.section.sort")) {
                    ForEach(ItemSortOption.allCases) { option in
                        NavigationLink(value: AppDestination.itemSortList(packID: pack.id, sort: option)) {
                            HStack {
                                Text(option.title)
                                    .font(FONT_MEMO)
                                    .foregroundStyle(COLOR_MEMO)
                                Spacer()
                            }
                            .frame(minHeight: rowHeight)
                            .overlay(alignment: .bottom) {
                                // 独自の下線
                                COLOR_LIST_SEPARATOR
                                    .frame(height: LIST_SEPARATOR_THICKNESS)
                                    .ignoresSafeArea(edges: .horizontal)
                                    .padding(.horizontal, 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .padding(.horizontal, 32)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
            .padding(.horizontal, 0)
            .navigationTitle(pack.name.placeholderText("placeholder.pack.new"))
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(isShowingPopup)
                    .padding(.trailing, 8)

                    Button {
                        canUndo = false
                        modelContext.undoManager?.performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo || isShowingPopup)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        canRedo = false
                        modelContext.undoManager?.performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo || isShowingPopup)
                    .padding(.trailing, 8)

                    Button(action: addGroup) {
                        Image(systemName: "plus.square")
                    }
                    .disabled(isShowingPopup)
                }
            }
            .onAppear {
                updateUndoRedo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }

            //----------------------------------
            //(ZStack 1) Popupで表示
            if let group = editingGroup {
                PopupView(anchor: popupAnchor) {
                    editingGroup = nil
                    popupAnchor = nil
                } content: {
                    GroupEditView(group: group) {
                        //.onClose：内から閉じる場合
                        editingGroup = nil
                        popupAnchor = nil
                    }
                }
                .zIndex(1)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    if isShowingPopup {
                        guard abs(horizontal) > 80 || abs(vertical) > 80 else { return }
                        editingGroup = nil
                        popupAnchor = nil
                        return
                    }

                    guard horizontal > 80, abs(vertical) < 50 else { return }
                    dismiss()
                }
        )
    }

    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo && modelContext.hasChanges // && 編集なければ非活性
            canRedo = um.canRedo
        } else {
            canUndo = false
            canRedo = false
        }
    }

    private func addGroup() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        let newOrder: Int
        switch insertionPosition {
        case .head:
            let minOrder = pack.child.map { $0.order }.min() ?? 0
            newOrder = minOrder - 1
        case .tail:
            let maxOrder = pack.child.map { $0.order }.max() ?? -1
            newOrder = maxOrder + 1
        }

        let newGroup = M2Group(name: "", order: newOrder, parent: pack)
        modelContext.insert(newGroup)
        withAnimation {
            switch insertionPosition {
            case .head:
                pack.child.insert(newGroup, at: 0)
            case .tail:
                pack.child.append(newGroup)
            }
            pack.normalizeGroupOrder()
        }
    }

    private func moveGroup(from source: IndexSet, to destination: Int) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        var groups = sortedGroups
        groups.move(fromOffsets: source, toOffset: destination)
        for (index, group) in groups.enumerated() {
            group.order = index
        }
        pack.child = groups
    }
}


#Preview {
    GroupListView(pack: M1Pack(name: "", order: 0))
}
