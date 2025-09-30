//
//  ItemSortListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/30.
//

import SwiftUI
import SwiftData

/// 並べ替え一覧
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
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

/// 並べ替え一覧メニュー定義
enum ItemSortOption: String, CaseIterable, Identifiable, Codable {
    // 以下の順に表示される
    case unchecked
    case lackCount
    case lackWeight
    case stockWeight
    
    // Row.ID
    var id: String { rawValue }
    // Row.タイトル
    var title: LocalizedStringKey {
        switch self {
            case .lackCount:
                return "item.sort.title.lackCount" //"不足個数順"
            case .lackWeight:
                return "item.sort.title.lackWeight" //"不足重量順"
            case .stockWeight:
                return "item.sort.title.stockWeight" //"在庫重量順"
            case .unchecked:
                return "item.sort.title.unchecked" //"未チェック順"
        }
    }
    
    // Sort条件
    /// pack配下の全Itemを並べ替える
    /// - Parameter pack: M1Pack
    /// - Returns: 並べ替えられたItem配列
    func sortedItems(from pack: M1Pack) -> [M3Item] {
        // pack配下の全Group
        let groups = pack.child.sorted { $0.order < $1.order }
        // pack配下の全Item
        let items = groups.flatMap { group in
            group.child.sorted { $0.order < $1.order }
        }
        
        switch self {
            case .lackCount:
                return items.sorted(by: { lhs, rhs in
                    compare(lhs: lhs,
                            rhs: rhs,
                            primary: lhs.need - lhs.stock,
                            rhsPrimary: rhs.need - rhs.stock)
                })
            case .lackWeight:
                return items.sorted(by: { lhs, rhs in
                    let lhsValue = (lhs.need - lhs.stock) * lhs.weight
                    let rhsValue = (rhs.need - rhs.stock) * rhs.weight
                    return compare(lhs: lhs,
                                   rhs: rhs,
                                   primary: lhsValue,
                                   rhsPrimary: rhsValue)
                })
            case .stockWeight:
                return items.sorted(by: { lhs, rhs in
                    let lhsValue = lhs.stock * lhs.weight
                    let rhsValue = rhs.stock * rhs.weight
                    return compare(lhs: lhs,
                                   rhs: rhs,
                                   primary: lhsValue,
                                   rhsPrimary: rhsValue)
                })
            case .unchecked:
                return items.sorted(by: { lhs, rhs in
                    let lhsValue = uncheckedKey(for: lhs)
                    let rhsValue = uncheckedKey(for: rhs)
                    if lhsValue != rhsValue {
                        return lhsValue < rhsValue
                    }
                    // 同じとき、Groupに遡って比較する
                    return fallbackCompare(lhs: lhs, rhs: rhs)
                })
        }
    }
    // 比較
    private func compare(lhs: M3Item, rhs: M3Item,
                         primary: Int, rhsPrimary: Int) -> Bool {
        if primary != rhsPrimary {
            return primary > rhsPrimary
        }
        // 同じとき、Groupに遡って比較する
        return fallbackCompare(lhs: lhs, rhs: rhs)
    }
    // Groupに遡って比較する
    private func fallbackCompare(lhs: M3Item, rhs: M3Item) -> Bool {
        let lhsGroupOrder = lhs.parent?.order ?? Int.max
        let rhsGroupOrder = rhs.parent?.order ?? Int.max
        if lhsGroupOrder != rhsGroupOrder {
            return lhsGroupOrder < rhsGroupOrder
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.id < rhs.id
    }
    /// 未チェック一覧のソート条件
    private func uncheckedKey(for item: M3Item) -> Int {
        if item.check {
            if item.need == 0 {
                return 4 // チェック＆不要
            }
            else if item.stock < item.need {
                return 2 // チェック＆不足
            }
            return 3 // チェック
        }else{
            if item.need == 0 {
                return 5 // 未チェック＆不要
            }
            else if item.stock < item.need {
                return 0 // 未チェック＆不足
            }
            return 1 // 未チェック＆充足
        }
    }
}


#Preview {
    ItemSortListView(pack: M1Pack(name: "", order: 0), sortOption: .lackCount)
}
