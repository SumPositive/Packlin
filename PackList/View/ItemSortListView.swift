//
//  ItemSortListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/30.
//

import SwiftUI
import SwiftData
import FirebaseAnalytics

/// 並べ替え一覧
struct ItemSortListView: View {
    let pack: M1Pack
    let sortOption: ItemSortOption

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKey.autoItemReorder) private var autoItemReorder: Bool = false

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?
    @State private var cachedItems: [M3Item] = []
    @State private var searchText: String = ""

    private var baseSortedItems: [M3Item] {
        sortOption.sortedItems(from: pack).filter { $0.parent != nil }
    }

    private var displayedItems: [M3Item] {
        autoItemReorder ? baseSortedItems : cachedItems
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [M3Item] {
        let keyword = trimmedSearchText
        guard !keyword.isEmpty else { return displayedItems }
        return displayedItems.filter { item in
            item.name.localizedCaseInsensitiveContains(keyword) ||
            item.memo.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var baseSortedItemIDs: [M3Item.ID] {
        baseSortedItems.map(\.id)
    }

    private var isShowingPopup: Bool { editingItem != nil }

    private let headerHeight: CGFloat = 44

    var body: some View {
        ZStack {
            VStack {
                // アイテムを検索
                searchHeader
                // 並べ替え一覧
                List {
                    Section {
                        ForEach(filteredItems) { item in
                            if let group = item.parent {
                                NavigationLink(
                                    value: AppDestination.itemEdit(
                                        packID: pack.id,
                                        groupID: group.id,
                                        itemID: item.id,
                                        sort: sortOption
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
                                .listRowBackground(COLOR_ROW_BACK)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .padding(.leading, 0)
                .padding(.trailing, 8)

                // 編集操作に応じて自動で並び替え
                Toggle(isOn: $autoItemReorder) {
                    HStack(spacing: 0) {
                        Spacer()
                        Image(systemName: "arrow.up.and.down.and.sparkles")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            .padding(8)

                        Text("変更あればすぐに並べ替える")
                            .font(.body)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.trailing, 16)
            }
            .navigationTitle(sortOption.title)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                // 並べ替え画面用のカスタムヘッダー
                HStack(spacing: 0) {
                    // 閉じる
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isShowingPopup)
                    .padding(.horizontal, 12)

                    // Undo
                    Button {
                        canUndo = false
                        modelContext.undoManager?.performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .imageScale(.small)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canUndo || isShowingPopup)
                    .padding(.horizontal, 12)

                    Spacer(minLength: 0)

                    Text(sortOption.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    // Redo
                    Button {
                        canRedo = false
                        modelContext.undoManager?.performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .imageScale(.small)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canRedo || isShowingPopup)
                    .padding(.horizontal, 12)

                    // スペース
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 24)
                        .padding(.horizontal, 12)
                }
                .tint(.primary)
                .frame(height: headerHeight)
                .padding(.horizontal, 8)
                .background(.thinMaterial)
            }
            .onAppear {
                updateUndoRedo()
                refreshDisplayedItems(forceReset: true)
                GALogger.log(.function(name: "item_sort", option: sortOption.rawValue))
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }
            .onChange(of: !autoItemReorder) { _, _ in
                refreshDisplayedItems(forceReset: true)
            }
            .onChange(of: baseSortedItemIDs) { _, _ in
                refreshDisplayedItems()
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
                        if abs(horizontal) <= 80 && abs(vertical) <= 80 { return }
                        editingItem = nil
                        popupAnchor = nil
                        return
                    }

                    if horizontal <= 80 || abs(vertical) >= 50 { return }
                    dismiss()
                }
        )
    }

    /// アイテムを検索
    private var searchHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(LocalizedStringKey("アイテムを検索"), text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !trimmedSearchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey("クリア"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .padding(.horizontal, 50)
        .padding(.bottom, 4)
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

    private func refreshDisplayedItems(forceReset: Bool = false) {
        let items = baseSortedItems

        guard !autoItemReorder else {
            cachedItems = items
            return
        }

        if forceReset || cachedItems.isEmpty {
            cachedItems = items
            return
        }

        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var updated = cachedItems.compactMap { map[$0.id] }
        let existingIDs = Set(updated.map { $0.id })
        let appended = items.filter { !existingIDs.contains($0.id) }
        updated.append(contentsOf: appended)

        cachedItems = updated
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
    var title: String {
        switch self {
            case .unchecked:
                return String(localized: "未チェック順")
            case .lackCount:
                return String(localized: "不足個数順")
            case .lackWeight:
                return String(localized: "不足重量順")
            case .stockWeight:
                return String(localized: "在庫重量順")
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
                return items.sorted(by: { ll, rr in
                    compare(ll: ll,
                            rr: rr,
                            primary: ll.need - ll.stock,
                            rrPrimary: rr.need - rr.stock)
                })
            case .lackWeight:
                return items.sorted(by: { ll, rr in
                    let llValue = (ll.need - ll.stock) * ll.weight
                    let rrValue = (rr.need - rr.stock) * rr.weight
                    return compare(ll: ll,
                                   rr: rr,
                                   primary: llValue,
                                   rrPrimary: rrValue)
                })
            case .stockWeight:
                return items.sorted(by: { ll, rr in
                    let llValue = ll.stock * ll.weight
                    let rrValue = rr.stock * rr.weight
                    return compare(ll: ll,
                                   rr: rr,
                                   primary: llValue,
                                   rrPrimary: rrValue)
                })
            case .unchecked:
                return items.sorted(by: { ll, rr in
                    let llValue = uncheckedKey(for: ll)
                    let rrValue = uncheckedKey(for: rr)
                    if llValue != rrValue {
                        return llValue < rrValue
                    }
                    // 同じとき、Groupに遡って比較する
                    return fallbackCompare(ll: ll, rr: rr)
                })
        }
    }
    // 比較
    private func compare(ll: M3Item, rr: M3Item,
                         primary: Int, rrPrimary: Int) -> Bool {
        if primary != rrPrimary {
            return primary > rrPrimary
        }
        // 同じとき、Groupに遡って比較する
        return fallbackCompare(ll: ll, rr: rr)
    }
    // Groupに遡って比較する
    private func fallbackCompare(ll: M3Item, rr: M3Item) -> Bool {
        let llGroupOrder = ll.parent?.order ?? Int.max
        let rrGroupOrder = rr.parent?.order ?? Int.max
        if llGroupOrder != rrGroupOrder {
            return llGroupOrder < rrGroupOrder
        }
        if ll.order != rr.order {
            return ll.order < rr.order
        }
        return ll.id < rr.id
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
