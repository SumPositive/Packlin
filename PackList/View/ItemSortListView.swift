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
    @EnvironmentObject private var navigationStore: NavigationStore

    @AppStorage(AppStorageKey.autoItemReorder) private var autoItemReorder: Bool = DEF_autoItemReorder
    // PackListと共通の表示モードを参照し、初心者向け説明を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default

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
        // トグルのON/OFFに関わらず、キャッシュ側は最新順を握っておく
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

    // ボタン行＋タイトル行で表示しつつ、上下余白を抑えて高さをコンパクトにする
    private var headerHeight: CGFloat { isBeginnerMode ? 96 : 64 }
    // 説明文表示判定をまとめておく
    private var isBeginnerMode: Bool { displayMode == .beginner }

    // 並べ替えを切り替えるためのフッターメニュー
    private var sortFooterMenu: some View {
        VStack(spacing: 0) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
                .ignoresSafeArea(edges: .horizontal)

            HStack(spacing: 10) {
                ForEach(ItemSortOption.allCases) { option in
                    let isCurrent = option == sortOption

                    Button {
                        guard !isCurrent else { return }
                        // スタックを増やさずに並べ替え画面を差し替えて、戻る操作を1回に抑える
                        let destination = AppDestination.itemSortList(packID: pack.id, sort: option)
                        withAnimation(.easeInOut(duration: 0.18)) {
                            navigationStore.replaceLast(with: destination)
                        }
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isCurrent)
                    // 選択中は押せないと分かるように透過度を少し下げる
                    .opacity(isCurrent ? 0.7 : 1.0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
    }

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
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                // PackListと同じヘッダー構成で、視線移動しやすいボタン配置に揃える
                VStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 0) {
                        // 戻るボタンと初心者向け説明
                        VStack(spacing: 6) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isShowingPopup)

                            if isBeginnerMode {
                                Text("グループ一覧に戻る")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 76)
                        .padding(.horizontal, 6)

                        // Undoと説明
                        VStack(spacing: 6) {
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

                            if isBeginnerMode {
                                Text("直前の変更を元に戻す")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 76)
                        .padding(.horizontal, 6)

                        Spacer(minLength: 0)

                        // Redoと説明
                        VStack(spacing: 6) {
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

                            if isBeginnerMode {
                                Text("Undoをやり直す")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 76)
                        .padding(.horizontal, 6)

                        // 変更があればすぐに並べ替えるトグルをアイコン化して右端に集約
                        VStack(spacing: 6) {
                            Button {
                                autoItemReorder.toggle()
                                // OFF→ONでもキャッシュを最新の並び順に揃える
                                refreshDisplayedItems(forceReset: true, forceResort: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: autoItemReorder ? "arrow.up.and.down.and.sparkles" : "arrow.up.arrow.down.square")
                                        .imageScale(.medium)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(autoItemReorder ? Color.accentColor : Color.secondary)
                                        .padding(8)

                                    if isBeginnerMode {
                                        Text("常時並べ替える")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .frame(maxWidth: isBeginnerMode ? nil : 44, alignment: .trailing)
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(maxWidth: 120)
                        .padding(.horizontal, 6)
                    }

                    // タイトルは2段目で1行固定にし、長い名称でも欠けにくくする
                    // 並べ替え条件も併記して、今どの一覧を見ているかを明示する
                    Text("\(pack.name.placeholder("新しいパック"))（\(sortOption.title)）")
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .tint(.primary)
                .frame(height: headerHeight)
                .padding(.horizontal, 8)
                // ヘッダーの上下余白を抑えてリスト領域を広げる
                .padding(.vertical, 3)
                .background(.thinMaterial)
            }
            .onAppear {
                updateUndoRedo()
                // ソート切り替え直後は自動並べ替えスイッチに関係なく最新順を採用
                refreshDisplayedItems(forceReset: true, forceResort: true)
                GALogger.log(.function(name: "item_sort", option: sortOption.rawValue))
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }
            .onChange(of: autoItemReorder) { _, _ in
                // スイッチのON/OFFを問わず、一度は最新の並べ替えを反映する
                refreshDisplayedItems(forceReset: true, forceResort: true)
            }
            .onChange(of: baseSortedItemIDs) { _, _ in
                // 並びに変更があった場合は現在のモードを尊重しつつキャッシュを更新
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

                    if horizontal <= 80 { return }
                    if abs(vertical) < 50 {
                        dismiss()
                    }
                }
        )
        .safeAreaInset(edge: .bottom) {
            sortFooterMenu
        }
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

    private func refreshDisplayedItems(forceReset: Bool = false, forceResort: Bool = false) {
        let items = baseSortedItems

        guard !autoItemReorder else {
            cachedItems = items
            return
        }

        // 並べ替えスイッチがOFFでも、指示されたときは最新順に戻す
        if forceResort {
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
            // できるだけ「<」向きで比較し、どちらが大きいかを明示する
            return rrPrimary < primary
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
