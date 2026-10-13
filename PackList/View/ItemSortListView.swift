//  アイテム縦覧画面
//  全アイテムの検索、並べ替え、条件別表示をまとめる
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseAnalytics

/// 並べ替え一覧
struct ItemSortListView: View {
    let pack: M1Pack
    let sortOption: ItemSortOption

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationStore: NavigationStore
    @EnvironmentObject private var history: UndoStackService

    // PackListと共通の表示モードを参照し、初心者向け説明を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    @AppStorage(AppStorageKey.rowTextLines) private var rowTextLines: RowTextLines = .default

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?
    @State private var cachedItems: [M3Item] = []
    @State private var searchText: String = ""
    /// 検索欄の入力中か（キーボード外のタップで閉じるため）
    @FocusState private var isSearchFocused: Bool
    /// 絞り込みに選んだタグ（単一選択。そのタグが付いたアイテムだけを表示する）
    @State private var selectedTag: String?
    /// 「タグなし」を選んだとき true（タグが1つも付いていないアイテムだけを表示する）
    /// selectedTag とは同時に選ばない
    @State private var isUntaggedSelected = false

    /// タグ一覧の表示行数（1〜tagMaxRows）。ハンドルの上下ドラッグで変更し永続化する
    @AppStorage(AppStorageKey.itemBrowseTagRows) private var tagRows: Int = 2
    /// タグボタン1行分の実測高さ（0 は未測定）
    @State private var tagChipHeight: CGFloat = 0
    /// タグ一覧全体の実測高さ（0 は未測定）
    @State private var tagContentHeight: CGFloat = 0
    /// ドラッグ開始時の行数（ドラッグ中だけ値を持つ）
    @State private var tagRowsAtDragStart: Int?
    /// タグ式の「まとめて」選択モード
    @State private var isBulkMode = false
    @State private var selectedBulkIDs: Set<M3Item.ID> = []
    @State private var isShowingBulkTagSheet = false
    @State private var isShowingBulkUntagSheet = false
    @State private var isShowingBulkCopySheet = false
    @State private var isConfirmingBulkDelete = false
    /// まとめて操作の結果（コピー完了など）
    @State private var bulkResultMessage: String?
    /// タグ式でシートに出しているアイテム
    @State private var detailItem: M3Item?
    /// シートで表示中のアイテム（前へ・次へで変わる）。一覧の行を強調表示する
    @State private var highlightedItemID: M3Item.ID?
    /// シートを最初から広げて開くか（新しいアイテムを追加したとき）
    @State private var detailStartsExpanded = false
    /// 並べ替え条件プルダウンの展開状態
    @State private var isSortPickerExpanded = false
    /// 逆順にしている並べ替え条件。同じ条件をもう一度選ぶと切り替わり、別の条件を選ぶと正順へ戻す
    @AppStorage(AppStorageKey.itemBrowseReversedSort) private var reversedSortRaw = ""
    private var isSortReversed: Bool { reversedSortRaw == sortOption.rawValue }

    private var baseSortedItems: [M3Item] {
        sortOption.sortedItems(from: pack, reversed: isSortReversed).filter { $0.parent != nil }
    }

    /// 表示順は常に固定（常時並べ替えは廃止）。変更しても行は動かさず、並べ替え条件のタップで並べ直す
    private var displayedItems: [M3Item] { cachedItems }

    /// 表示中の並びが、今の並べ替え条件の最新順からずれているか
    /// ずれていれば並べ替え条件をグレーにして、タップで並べ直せることを示す
    private var isSortOutdated: Bool {
        cachedItems.map(\.id) != baseSortedItemIDs
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [M3Item] {
        let keyword = trimmedSearchText
        guard !keyword.isEmpty || selectedTag != nil || isUntaggedSelected else { return displayedItems }
        return displayedItems.filter { item in
            // 選んだタグが付いているものに絞る
            if let selectedTag, !item.tags.contains(selectedTag) { return false }
            if isUntaggedSelected, !item.tags.isEmpty { return false }
            guard !keyword.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(keyword) ||
                item.memo.localizedCaseInsensitiveContains(keyword) ||
                item.tags.contains { $0.localizedCaseInsensitiveContains(keyword) }
        }
    }

    /// 検索欄の下に出すタグ一覧
    /// 入力中はその文字を含むタグに絞るが、選択中のタグは外せるよう常に残す
    private var visibleTags: [String] {
        let tags = pack.tagsByItemCount
        let keyword = trimmedSearchText
        guard !keyword.isEmpty else { return tags }
        return tags.filter { $0 == selectedTag || $0.localizedCaseInsensitiveContains(keyword) }
    }

    private var baseSortedItemIDs: [M3Item.ID] {
        baseSortedItems.map(\.id)
    }

    private var isShowingPopup: Bool { editingItem != nil }

    /// タグ式パックではこの画面がパック直下になる（グループ一覧を経由しない）
    private var isTagMode: Bool { pack.classifyMode == .tag }

    // 説明文表示判定をまとめておく
    private var isBeginnerMode: Bool { displayMode == .beginner }
    /// ヘッダー左右の余白。アイテム編集画面と同じく、大きい文字では詰めてボタン位置を揃える
    private var headerHorizontalPadding: CGFloat {
        switch fontScale {
        case .large, .xLarge:
            return 8
        default:
            return 16
        }
    }

    // ヘッダーの高さを表示モードで変える
    private var headerHeight: CGFloat {
        // 初心者ヘルプを欠けさせないよう、文字サイズに応じてヘッダーを高くする
        isBeginnerMode ? appHeaderHeightForBeginner(fontScale) : appHeaderHeightForExpert(fontScale)
    }

    /// 並べ替え条件の見た目。並びが古いときは選択値をグレーにする
    private var sortPickerStyle: AZPickerStyle {
        var style = AZPickerStyle.form
        style.dropdownSelectedValueColor = isSortOutdated ? .secondary : .accentColor
        return style
    }

    /// 並べ替え条件ボタンの開閉。並びが古い（グレー）ときのタップは、開かずに並べ直してアクセント色へ戻す
    private var sortPickerExpansion: Binding<Bool> {
        Binding(
            get: { isSortPickerExpanded },
            set: { expanded in
                if expanded && isSortOutdated {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        refreshDisplayedItems(forceReset: true, forceResort: true)
                    }
                    return
                }
                isSortPickerExpanded = expanded
            }
        )
    }

    /// 昇順/降順を切り替えて並べ直す（右の昇降アイコンから）
    private func toggleSortDirection() {
        withAnimation(.easeInOut(duration: 0.18)) {
            reversedSortRaw = isSortReversed ? "" : sortOption.rawValue
            refreshDisplayedItems(forceReset: true, forceResort: true)
        }
    }

    /// 並べ替え条件の選択。選んだ条件の縦覧へ差し替える（旧フッターのボタンと同じ動き）
    private var sortSelection: Binding<ItemSortOption> {
        Binding(
            get: { sortOption },
            set: { option in
                // 同じ条件を選んだときは向きはそのままで並べ直す
                guard option != sortOption else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        refreshDisplayedItems(forceReset: true, forceResort: true)
                    }
                    return
                }
                // 別の条件は正順から始める
                reversedSortRaw = ""
                // スタックを増やさずに並べ替え画面を差し替えて、戻る操作を1回に抑える
                let destination = AppDestination.itemSortList(packID: pack.id, sort: option)
                withAnimation(.easeInOut(duration: 0.18)) {
                    navigationStore.replaceLast(with: destination)
                }
            }
        )
    }

    var body: some View {
        ZStack {
            VStack {
                // アイテムを検索
                searchHeader
                // 並べ替え一覧
                ScrollViewReader { listProxy in
                List {
                    Section {
                        ForEach(filteredItems) { item in
                            if let group = item.parent {
                                Group {
                                    if isTagMode {
                                        // タグ式は画面を移らず、シートで最小限の詳細を出す（広げると全部を編集）
                                        // 数量カプセルのタップも同じシートを開く（数量はシートで変える）
                                        // 「まとめて」選択中は、行のタップで選択を切り替える
                                        Button {
                                            if isBulkMode {
                                                toggleBulkSelection(item)
                                            } else {
                                                openDetailSheet(item, expanded: false)
                                            }
                                        } label: {
                                            ItemRowView(item: item,
                                                        isBulkMoveMode: isBulkMode,
                                                        isBulkMoveSelected: selectedBulkIDs.contains(item.id)) { selected, _ in
                                                openDetailSheet(selected, expanded: false)
                                            } onToggleBulkMoveSelection: {
                                                toggleBulkSelection(item)
                                            }
                                        }
                                    } else {
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
                                    }
                                }
                                .buttonStyle(.plain)
                                // シートで開いているアイテムの行を、薄いアクセント色と左端の帯で示す
                                .overlay {
                                    if highlightedItemID == item.id {
                                        ZStack(alignment: .leading) {
                                            Color.accentColor.opacity(0.10)
                                            Color.accentColor
                                                .frame(width: 4)
                                        }
                                        .allowsHitTesting(false)
                                    }
                                }
                                .id(item.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowBackground(COLOR_ROW_BACK)
                            }
                        }

                        // タグ式はグループ一覧が無いので、ここからアイテムを追加する
                        if isTagMode {
                            AppendAtEndRowView(systemImage: "plus.circle",
                                               fontScale: fontScale,
                                               showsText: isBeginnerMode,
                                               trailingAccessory: AnyView(displayedWeightTotal),
                                               leadingAccessory: isBulkMode ? nil : AnyView(bulkStartButton)) {
                                addItemAndNavigate(source: "item_browse_append_end_row")
                            }
                            .disabled(isBulkMode)
                            .opacity(isBulkMode ? 0.45 : 1.0)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(COLOR_ROW_BACK)
                            // 高さは AppendAtEndRowView 内側の padding(.vertical, 8) で自動調整される
                            .environment(\.defaultMinListRowHeight, 0)
                        }
                    }
                }
                .listStyle(.plain)
                // 一覧をスクロールしたらキーボードを閉じる
                .scrollDismissesKeyboard(.immediately)
                // 入力中に一覧をタップしたら、行を開かずにキーボードだけ閉じる
                .overlay {
                    if isSearchFocused {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { isSearchFocused = false }
                    }
                }
                .scrollIndicators(.hidden, axes: .vertical)
                .listRowSeparator(.hidden)
                .padding(.leading, 0)
                .padding(.trailing, 8)
                .environment(\.defaultMinListRowHeight, rowTextLines.usesExtraSmallItemRow ? 38 : 44)
                // シートで開いた行が下のシートに隠れないよう、画面の上寄りまでスクロールする
                .onChange(of: highlightedItemID) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        listProxy.scrollTo(newID, anchor: UnitPoint(x: 0.5, y: 0.2))
                    }
                }
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                // PackListと同じヘッダー構成で、視線移動しやすいボタン配置に揃える
                VStack(alignment: .center, spacing: 6) {
                    // アイテム編集・アイテム一覧と同じく上下中央揃えにして、ボタン位置を揃える
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
                                Text(LocalizedStringKey(isTagMode ? "back.packs" : "back.groups"))
                                    .font(.caption2)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.7)
                                    .allowsTightening(true)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 50)
                        .padding(.horizontal, 4)

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
                                Text("undo.last.change")
                                    .font(.caption2)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.7)
                                    .allowsTightening(true)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 55)
                        .padding(.horizontal, 4)

                        Spacer()
                        
                        if isBeginnerMode {
                            Text("item.browse")
                                .font(.system(size: 15))
                                .lineLimit(3)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                                .frame(minWidth: 50)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }

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
                                Text("redo.undone.change")
                                    .font(.caption2)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.7)
                                    .allowsTightening(true)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 55)
                        .padding(.horizontal, 4)

                        if isTagMode {
                            // 新しいアイテム追加と説明（タグ式のみ。グループ式はグループ内で追加する）
                            VStack(spacing: 6) {
                                Button {
                                    addItemAndNavigate(source: "item_browse_header")
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .imageScale(.large)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(COLOR_ADD_ACTION)
                                }
                                .buttonStyle(.borderless)
                                .disabled(isShowingPopup || isBulkMode)

                                if isBeginnerMode {
                                    Text("add.new.item")
                                        .font(.caption2)
                                        .lineLimit(3)
                                        .minimumScaleFactor(0.7)
                                        .allowsTightening(true)
                                        .foregroundStyle(COLOR_ADD_ACTION)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(width: 74)
                            .padding(.horizontal, 4)
                        } else {
                            Spacer(minLength: 66)
                        }
                    }

                    // パック名のみのパンくずも最大幅を1/4に抑えて表示する
                    BreadcrumbView(
                        packName: pack.name.placeholder("new.pack"),
                        groupName: nil,
                        itemName: sortOption.title,
                        rootAction: { navigationStore.path = NavigationPath() },
                        packAction: { navigationStore.path = NavigationPath([AppDestination.groupList(packID: pack.id)]) },
                        groupAction: nil,
                        itemAction: nil
                    )
                }
                // iPadマルチウィンドウの左上システムアイコンに押し込まれないよう、ヘッダーを右へオフセットする
                .padding(.leading, ipadWindowControlInset())
                .tint(.primary)
                .frame(height: headerHeight)
                .padding(.horizontal, headerHorizontalPadding)
                // ヘッダーの上下余白を抑えてリスト領域を広げる
                .padding(.vertical, 3)
                .background(.thinMaterial)
                // 初心者ヘルプ・タイトル・パンくずを「大」までで頭打ち
                .cappedAtLargeFontSize()
            }
            .onAppear {
                updateUndoRedo()
                // ソート切り替え直後は自動並べ替えスイッチに関係なく最新順を採用
                refreshDisplayedItems(forceReset: true, forceResort: true)
                // 縦覧ソートの利用種別を集計する
                GALogger.log(.feature_use(name: "item_browse", source: "group_list_footer", detail: sortOption.rawValue))
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }
            .onChange(of: baseSortedItemIDs) { _, _ in
                // 並びに変更があっても行は動かさず、追加・削除だけ反映する
                refreshDisplayedItems()
            }
            // 並べ替え条件や向きが変わったときは必ず並べ直す
            // 条件の切り替えは画面を差し替えるが、同じ型の画面が使い回されて onAppear が呼ばれないことがある
            .onChange(of: sortOption) { _, _ in
                refreshDisplayedItems(forceReset: true, forceResort: true)
            }
            .onChange(of: isSortReversed) { _, _ in
                refreshDisplayedItems(forceReset: true, forceResort: true)
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
        // 「まとめて」選択中だけ、下部に選択数と操作メニューを出す
        .safeAreaInset(edge: .bottom) {
            if isBulkMode {
                bulkFooter
            }
        }
        .sheet(isPresented: $isShowingBulkTagSheet) {
            BulkTagSheet(pack: pack, items: selectedBulkItems, mode: .add) { tags in
                applyBulkTags(tags)
                isShowingBulkTagSheet = false
            }
            .appFontScale(fontScale)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingBulkUntagSheet) {
            BulkTagSheet(pack: pack, items: selectedBulkItems, mode: .remove) { tags in
                removeBulkTags(tags)
                isShowingBulkUntagSheet = false
            }
            .appFontScale(fontScale)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingBulkCopySheet) {
            BulkCopyPackSheet(sourcePack: pack, itemCount: selectedBulkItems.count) { destination in
                copyBulkItems(to: destination)
                isShowingBulkCopySheet = false
            }
            .appFontScale(fontScale)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("bulk.delete.title", isPresented: $isConfirmingBulkDelete) {
            Button("delete", role: .destructive) {
                deleteBulkItems()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "bulk.delete.message"), selectedBulkItems.count))
        }
        .alert(bulkResultMessage ?? "", isPresented: Binding(
            get: { bulkResultMessage != nil },
            set: { if !$0 { bulkResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $detailItem, onDismiss: { highlightedItemID = nil }) { item in
            ItemDetailSheet(pack: pack,
                            item: item,
                            startsExpanded: detailStartsExpanded,
                            adjacentItemProvider: { current, offset in
                                adjacentDisplayedItem(from: current, offset: offset)
                            },
                            onCurrentItemChange: { current in
                                highlightedItemID = current.id
                            })
            .appFontScale(fontScale)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    if isShowingPopup {
                        if abs(horizontal) <= 80 && abs(vertical) <= 80 { return }
                        return
                    }

                    if horizontal <= 80 { return }
                    if abs(vertical) < 50 {
                        dismiss()
                    }
                }
        )
    }

    /// タグ式のアイテム追加：「タグ式グループ」の末尾へ追加して、広げたアイテムシートで開く
    /// 縦覧は並べ替え表示なので、ヘッダーと末尾セルのどちらから追加しても同じ動きにする
    private func addItemAndNavigate(source: String) {
        GALogger.log(.operation(name: "add", target: "item", source: source, detail: "tail", count: nil))
        var newItem: M3Item?

        history.perform(context: modelContext) {
            let group = pack.groupForNewItem()
            let items = group.child.sorted { $0.order < $1.order }
            let newOrder = sparseOrderForInsertion(items: items, index: items.count) {
                // order のみを整え、child 配列を並べ替えない
                normalizeSparseOrders(items)
            }
            // 絞り込み中のタグがあれば最初から付けておく（追加直後に一覧から消えないように）
            let item = M3Item(name: "",
                              tags: selectedTag.map { [$0] } ?? [],
                              order: newOrder,
                              parent: group)
            modelContext.insert(item)
            newItem = item
        }

        // 新しいアイテムは名称から入力するので、シートを最初から広げて開く
        if let newItem {
            openDetailSheet(newItem, expanded: true)
        }
    }

    /// 表示中（絞り込み後）のアイテムの合計重量。パック行と同じ表記で末尾追加の行の右端に出す
    private var displayedWeightTotal: some View {
        let items = filteredItems
        let stockWeight = items.reduce(0) { $0 + $1.weight * $1.stock }
        let needWeight = items.reduce(0) { $0 + $1.weight * $1.need }
        let isSufficient = !items.isEmpty && items.allSatisfy { $0.need == 0 || $0.need <= $0.stock }
        return WeightTotalCapsule(stockWeight: stockWeight,
                                  needWeight: needWeight,
                                  isSufficient: isSufficient)
    }

    // MARK: - まとめて（タグ式）

    /// 「まとめて」選択を始めるボタン（末尾追加の行の左端）
    private var bulkStartButton: some View {
        Button(action: beginBulkMode) {
            Text("bulk.select")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(COLOR_BULK)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(COLOR_BULK.opacity(0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(COLOR_BULK.opacity(0.5), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(filteredItems.isEmpty)
        .cappedAtLargeFontSize()
    }

    /// 選択中の下部：取消・選択数（全選択の切り替え）・操作メニュー
    private var bulkFooter: some View {
        VStack(spacing: 0) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
                .ignoresSafeArea(edges: .horizontal)

            HStack(spacing: 10) {
                Button("cancel") {
                    endBulkMode()
                }
                .buttonStyle(.bordered)
                .tint(COLOR_BULK)

                // 表示中（絞り込み後）のアイテムをまとめて選ぶ・外す
                Button {
                    toggleSelectAllDisplayed()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: String(localized: "bulk.selected.count"), selectedBulkItems.count))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(LocalizedStringKey(isAllDisplayedSelected ? "bulk.deselect.all" : "bulk.select.all"))
                            .font(.caption)
                            .foregroundStyle(COLOR_BULK)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        isShowingBulkTagSheet = true
                    } label: {
                        Label("bulk.action.tag", systemImage: "tag")
                    }
                    Button {
                        isShowingBulkUntagSheet = true
                    } label: {
                        Label("bulk.action.untag", systemImage: "tag.slash")
                    }
                    // 選んだアイテムにタグが1つも無ければ外せない
                    .disabled(selectedBulkItems.allSatisfy { $0.tags.isEmpty })
                    Button {
                        isShowingBulkCopySheet = true
                    } label: {
                        Label("bulk.action.copy", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        isConfirmingBulkDelete = true
                    } label: {
                        Label("delete", systemImage: "trash")
                    }
                } label: {
                    Text("bulk.action")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(COLOR_BULK))
                        .foregroundStyle(.white)
                }
                .disabled(selectedBulkItems.isEmpty)
                .opacity(selectedBulkItems.isEmpty ? 0.45 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
        }
        .cappedAtLargeFontSize()
    }

    /// 選択中のアイテム（並びは表示順。絞り込みで見えなくなった選択も含める）
    private var selectedBulkItems: [M3Item] {
        baseSortedItems.filter { selectedBulkIDs.contains($0.id) }
    }

    private var isAllDisplayedSelected: Bool {
        let displayed = filteredItems
        return !displayed.isEmpty && displayed.allSatisfy { selectedBulkIDs.contains($0.id) }
    }

    private func beginBulkMode() {
        editingItem = nil
        popupAnchor = nil
        isSearchFocused = false
        selectedBulkIDs.removeAll()
        isBulkMode = true
        GALogger.log(.feature_use(name: "bulk_action", source: "item_browse", detail: "start"))
    }

    private func endBulkMode() {
        selectedBulkIDs.removeAll()
        isBulkMode = false
    }

    private func toggleBulkSelection(_ item: M3Item) {
        if selectedBulkIDs.contains(item.id) {
            selectedBulkIDs.remove(item.id)
        } else {
            selectedBulkIDs.insert(item.id)
        }
    }

    /// 表示中のアイテムを全部選ぶ。全部選ばれていれば表示中の分を外す
    private func toggleSelectAllDisplayed() {
        let displayedIDs = Set(filteredItems.map(\.id))
        if isAllDisplayedSelected {
            selectedBulkIDs.subtract(displayedIDs)
        } else {
            selectedBulkIDs.formUnion(displayedIDs)
        }
    }

    /// 選んだアイテムにタグを付ける（既に付いていれば付け直さない。上限はタグの決まりに従う）
    private func applyBulkTags(_ tags: [String]) {
        let items = selectedBulkItems
        guard !items.isEmpty, !tags.isEmpty else { return }
        GALogger.log(.operation(name: "tag", target: "item", source: "bulk_action", detail: nil, count: items.count))
        history.perform(context: modelContext) {
            for item in items {
                let merged = M3Item.sanitizedTags(item.tags + tags)
                if merged != item.tags {
                    item.tags = merged
                }
            }
        }
        endBulkMode()
    }

    /// 選んだアイテムからタグを外す
    private func removeBulkTags(_ tags: [String]) {
        let items = selectedBulkItems
        guard !items.isEmpty, !tags.isEmpty else { return }
        GALogger.log(.operation(name: "untag", target: "item", source: "bulk_action", detail: nil, count: items.count))
        let removing = Set(tags)
        history.perform(context: modelContext) {
            for item in items where item.tags.contains(where: removing.contains) {
                item.tags.removeAll { removing.contains($0) }
            }
        }
        endBulkMode()
    }

    /// 選んだアイテムを別のパックへコピーする
    /// - タグ式のパックへは「タグ式グループ」に入れる
    /// - グループ式のパックへは、コピー元のパック名で新しいグループを作って入れる（どこから来たか分かるように）
    private func copyBulkItems(to destination: M1Pack) {
        let items = selectedBulkItems
        guard !items.isEmpty else { return }
        GALogger.log(.operation(name: "copy", target: "item", source: "bulk_action", detail: destination.classifyMode.rawValue, count: items.count))
        history.perform(context: modelContext) {
            let group: M2Group
            if destination.classifyMode == .tag {
                group = destination.groupForNewItem()
            } else {
                group = M2Group(name: pack.name, order: destination.nextGroupOrder(), parent: destination)
                modelContext.insert(group)
            }
            var order = group.nextItemOrder()
            for source in items {
                // 進捗（チェック・在庫）は引き継がない（パック複製と同じ）
                let copied = M3Item(name: source.name,
                                    memo: source.memo,
                                    check: false,
                                    stock: 0,
                                    need: source.need,
                                    weight: source.weight,
                                    tags: source.tags,
                                    order: order,
                                    parent: group)
                modelContext.insert(copied)
                order += ORDER_SPARSE
            }
        }
        bulkResultMessage = String(format: String(localized: "bulk.copy.done"),
                                   items.count,
                                   destination.name.isEmpty ? String(localized: "new.pack") : destination.name)
        endBulkMode()
    }

    /// 選んだアイテムを削除する
    private func deleteBulkItems() {
        let items = selectedBulkItems
        guard !items.isEmpty else { return }
        GALogger.log(.operation(name: "delete", target: "item", source: "bulk_action", detail: nil, count: items.count))
        history.perform(context: modelContext) {
            for item in items {
                item.delete()
            }
        }
        endBulkMode()
    }

    /// タグ式のアイテムシートを開く
    private func openDetailSheet(_ item: M3Item, expanded: Bool) {
        detailStartsExpanded = expanded
        detailItem = item
        highlightedItemID = item.id
    }

    /// シートの前へ・次へでたどる隣のアイテム（縦覧に表示中の並び・絞り込みのまま）
    private func adjacentDisplayedItem(from current: M3Item, offset: Int) -> M3Item? {
        guard offset != 0 else { return nil }
        let items = filteredItems
        guard let index = items.firstIndex(where: { $0.id == current.id }) else { return nil }
        let destination = index + offset
        return items.indices.contains(destination) ? items[destination] : nil
    }

    // タグ一覧のレイアウト定数
    private let tagRowSpacing: CGFloat = 8
    private let tagAreaVerticalPadding: CGFloat = 2
    private let tagMaxRows = 5

    /// タグボタン1行分の高さ（測れていればそれを、まだなら目安値を使う）
    private var tagRowHeight: CGFloat { 0 < tagChipHeight ? tagChipHeight : 34 }

    /// 指定行数に対応するタグ一覧の高さ
    private func tagAreaHeight(for rows: Int) -> CGFloat {
        let r = CGFloat(min(max(rows, 1), tagMaxRows))
        return tagRowHeight * r + tagRowSpacing * (r - 1) + tagAreaVerticalPadding * 2
    }

    /// 実際に見せる高さ。タグが少なければ中身の高さまで縮める
    private var tagAreaVisibleHeight: CGFloat {
        let limit = tagAreaHeight(for: tagRows)
        guard 0 < tagContentHeight else { return tagAreaHeight(for: 1) }
        return min(tagContentHeight, limit)
    }

    /// タグ一覧の高さを変えるハンドル。上下ドラッグで行数を1〜tagMaxRowsに増減する
    /// グローバル座標で指の移動量を測るので、ハンドル自身が動いても指との連動が崩れない
    private var tagResizeHandle: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)   // 中央寄せ＋タップ領域を横いっぱいに
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        let start = tagRowsAtDragStart ?? tagRows
                        if tagRowsAtDragStart == nil { tagRowsAtDragStart = start }
                        // 開始行数＋（移動量÷1行分）を四捨五入して目標行数にする
                        let delta = Int((value.translation.height / (tagRowHeight + tagRowSpacing)).rounded())
                        let target = min(max(start + delta, 1), tagMaxRows)
                        if target != tagRows {
                            tagRows = target
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in
                        tagRowsAtDragStart = nil
                    }
            )
            .accessibilityLabel(Text("tag.list.resize.a11y"))
    }

    /// タグとアイテムを検索
    private var searchHeader: some View {
        VStack(spacing: 6) {
            // 左に並べ替え条件、右に検索欄
            HStack(spacing: 8) {
                AZDropdownPicker(options: ItemSortOption.allCases,
                                 selection: sortSelection,
                                 isExpanded: sortPickerExpansion,
                                 minWidth: 100,
                                 style: sortPickerStyle) { option in
                    Text(option.title)
                }
                .cappedAtLargeFontSize()

                // 昇順/降順（クレメモの決済一覧と同じアイコン）。条件のプルダウンとは別にタップで切り替える
                Button(action: toggleSortDirection) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .scaleEffect(x: 1, y: isSortReversed ? -1 : 1)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSortOutdated ? Color.secondary : Color.accentColor)
                        .frame(width: 36, height: 36)
                        // 並べ替え条件のプルダウンと同じ見た目の真円で囲む
                        .background(
                            Circle().fill(AZPickerStyle.form.panelBackground)
                        )
                        .overlay(
                            Circle().strokeBorder(Color.secondary.opacity(AZPickerStyle.form.borderOpacity), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(AZPickerStyle.form.shadowOpacity),
                                radius: AZPickerStyle.form.shadowRadius, x: 0, y: AZPickerStyle.form.shadowY)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("sort.direction.toggle.a11y"))
                .cappedAtLargeFontSize()

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(LocalizedStringKey("search.tags.items"), text: $searchText)
                        .focused($isSearchFocused)
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
                        .accessibilityLabel(LocalizedStringKey("clear"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
            .padding(.horizontal, 16)

            // タグ一覧（選ぶとアイテムを絞り込む）。クレメモの「よくある決済」と同じく折り返して並べ、
            // 1行〜tagMaxRows 行の高さで表示する。溢れた行は縦スクロールで見せ、行数は下のハンドルで変える
            // パックにタグが1つでもあれば「タグなし」も並べる
            if !pack.allTags.isEmpty {
                let tags = visibleTags
                let untaggedIndex = untaggedChipIndex(in: tags)
                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        // 行末に空きがあれば、後ろにある収まる幅のタグを繰り上げて詰める（並び順より詰め込みを優先）
                        AZFlowLayout(spacing: 8,
                                     rowSpacing: tagRowSpacing,
                                     alignment: .leading,
                                     packToFill: true) {
                            ForEach(tags[..<untaggedIndex], id: \.self) { tag in
                                tagChip(tag)
                            }
                            TagChip(title: String(localized: "tag.none"),
                                    isSelected: isUntaggedSelected,
                                    isSpecial: true) {
                                isUntaggedSelected.toggle()
                                selectedTag = nil
                                isSearchFocused = false
                            }
                            // 「タグなし」は常にあるので、これで1行分の高さを測る
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                tagChipHeight = height
                            }
                            ForEach(tags[untaggedIndex...], id: \.self) { tag in
                                tagChip(tag)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, tagAreaVerticalPadding)
                        // 全体の高さを測り、行数ぶんより少なければその高さまで縮める
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            tagContentHeight = height
                        }
                    }
                    .frame(height: tagAreaVisibleHeight)
                    .scrollIndicators(.hidden)
                    .animation(.easeOut(duration: 0.18), value: tagRows)

                    // 1行に収まらないときだけハンドルを出す
                    if tagAreaHeight(for: 1) + 1 < tagContentHeight {
                        tagResizeHandle
                    }
                }
                // ハンドルを含めたタグ一覧を1枚のパネルとして見せる（タグボタンの白が映える薄いグレー）
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, tagAreaHeight(for: 1) + 1 < tagContentHeight ? 0 : 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                // タグの丸ボタンが大きくなりすぎないよう「大」までで頭打ち
                .cappedAtLargeFontSize()
            }
        }
        .padding(.bottom, 4)
        .onChange(of: pack.allTags) { _, newTags in
            // どのアイテムからも外されたタグは選択からも外す
            if let selectedTag, !newTags.contains(selectedTag) {
                self.selectedTag = nil
            }
            // タグが1つも無くなると一覧ごと消えるので「タグなし」の選択も外す
            if newTags.isEmpty {
                isUntaggedSelected = false
            }
        }
    }

    /// 絞り込み用のタグボタン
    private func tagChip(_ tag: String) -> some View {
        TagChip(title: tag, isSelected: tag == selectedTag) {
            // 選択中をもう一度押すと解除、別のタグを押すと切り替える
            selectedTag = (tag == selectedTag) ? nil : tag
            isUntaggedSelected = false
            // タグを選んだら絞り込み結果が見えるよう、キーボードを閉じる
            isSearchFocused = false
        }
    }

    /// 「タグなし」もアイテム数の多い順の位置に入れる（同数のときは通常のタグの後ろ）
    private func untaggedChipIndex(in tags: [String]) -> Int {
        let counts = pack.tagItemCounts
        let untaggedCount = pack.untaggedItemCount
        return tags.firstIndex { (counts[$0] ?? 0) < untaggedCount } ?? tags.count
    }

    private func updateUndoRedo() {
        // === Fix 10 関連: hasChanges 連動を撤去 ===
        // 旧版は `um.canUndo && modelContext.hasChanges` で「保存待ちの変更が無ければ
        // Undo も無効」というつもりだった。しかし Fix 2 で Undo/Redo 後に
        // context.save() を呼ぶようにしたため、Redo 直後は hasChanges が false に
        // 戻り、canUndo も常に false になる不具合が出ていた。
        //
        // UndoStackManager.canUndo は UndoStackService.canUndo を委譲しており、
        // 履歴スタックの実状態を反映する唯一の真実源。これだけを参照する。
        if let um = modelContext.undoManager {
            canUndo = um.canUndo
            canRedo = um.canRedo
        } else {
            canUndo = false
            canRedo = false
        }
    }

    private func refreshDisplayedItems(forceReset: Bool = false, forceResort: Bool = false) {
        let items = baseSortedItems

        // 指示されたときは最新順に戻す
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
                return String(localized: "unchecked.first")
            case .lackCount:
                return String(localized: "short.count")
            case .lackWeight:
                return String(localized: "short.weight")
            case .stockWeight:
                return String(localized: "stock.weight")
        }
    }

    /// フッターボタン用の短い2行タイトル
    var footerTitle: String {
        switch self {
            case .unchecked:
                return String(localized: "item.sort.unchecked.footerTitle")
            case .lackCount:
                return String(localized: "item.sort.lackCount.footerTitle")
            case .lackWeight:
                return String(localized: "item.sort.lackWeight.footerTitle")
            case .stockWeight:
                return String(localized: "item.sort.stockWeight.footerTitle")
        }
    }

    /// 初心者向けの説明文
    var beginnerGuide: String {
        switch self {
            case .unchecked:
                return String(localized: "use.final.check")
            case .lackCount:
                return String(localized: "when.check.by.count")
            case .lackWeight:
                return String(localized: "when.check.by.weight")
            case .stockWeight:
                return String(localized: "use.when.re.over.weight")
        }
    }

    // Sort条件
    /// pack配下の全Itemを並べ替える
    /// - Parameter pack: M1Pack
    /// - Returns: 並べ替えられたItem配列
    /// - Parameter reversed: true なら逆順（アイテム縦覧で同じ条件をもう一度選んだとき）
    func sortedItems(from pack: M1Pack, reversed: Bool) -> [M3Item] {
        let items = sortedItems(from: pack)
        return reversed ? Array(items.reversed()) : items
    }

    /// 縦覧で逆順にしている条件か（設定値を直接読む。前後移動など縦覧の外で並びを揃えるため）
    var isReversedInBrowse: Bool {
        UserDefaults.standard.string(forKey: AppStorageKey.itemBrowseReversedSort) == rawValue
    }

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
