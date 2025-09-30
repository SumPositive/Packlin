//
//  ItemSortListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SwiftData

struct ItemSortListView: View {
    let pack: M1Pack
    let sortOption: ItemSortOption

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?

    private var sortedItems: [M3Item] {
        sortOption.sortedItems(from: pack).filter { $0.parent != nil }
    }

    private var isShowingPopup: Bool { editingItem != nil }

    var body: some View {
        ZStack {
            List {
                ForEach(sortedItems) { item in
                    if let group = item.parent {
                        NavigationLink(
                            value: AppDestination.itemEdit(
                                packID: pack.id,
                                groupID: group.id,
                                itemID: item.id
                            )
                        ) {
                            ItemRowView(item: item) { selected, point in
                                editingItem = selected
                                popupAnchor = point
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(COLOR_ROW_ITEM)
                        .disabled(isShowingPopup)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .padding(.leading, 0)
            .padding(.trailing, 8)
            .navigationTitle(sortOption.title)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                navigationToolbar
            }
            .onAppear {
                updateUndoRedo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }

            if let item = editingItem {
                PopupView(anchor: popupAnchor) {
                    editingItem = nil
                    popupAnchor = nil
                } content: {
                    ItemQuickEditView(item: item)
                }
                .zIndex(1)
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    if isShowingPopup {
                        guard abs(horizontal) > 80 || abs(vertical) > 80 else { return }
                        editingItem = nil
                        popupAnchor = nil
                        return
                    }

                    guard horizontal > 80, abs(vertical) < 50 else { return }
                    dismiss()
                }
        )
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button(action: {
                dismiss()
            }) {
                HStack(spacing: 0) {
                    Image(systemName: "chevron.backward")
                }
            }
            .padding(.trailing, 8)
            .disabled(isShowingPopup)

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
        }
    }

    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo && modelContext.hasChanges
            canRedo = um.canRedo
        } else {
            canUndo = false
            canRedo = false
        }
    }
}

#Preview {
    ItemSortListView(pack: M1Pack(name: "", order: 0), sortOption: .lackCount)
}
