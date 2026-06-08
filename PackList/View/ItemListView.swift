//  アイテム一覧画面
//  アイテム表示、末尾追加、まとめて移動、グループ編集導線をまとめる
//

import SwiftUI
import SwiftData

struct ItemListView: View {
    let pack: M1Pack
    let group: M2Group

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: UndoStackService
    @EnvironmentObject private var navigationStore: NavigationStore

    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    // PackListと共通の表示モードを参照し、初心者向け説明を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    @AppStorage(AppStorageKey.rowTextLines) private var rowTextLines: RowTextLines = .default
    // 不揮発保存：単体移動とまとめて移動で前回の移動先を共有する
    @AppStorage("itemEdit.move.lastPackID") private var lastMovePackID: String = ""
    @AppStorage("itemEdit.move.lastGroupID") private var lastMoveGroupID: String = ""
    @AppStorage("itemEdit.move.lastInsertPosition") private var lastMoveInsertPositionRawValue: String = ItemEditView.MoveInsertPosition.end.rawValue
    @AppStorage("itemEdit.move.lastKeepOriginal") private var lastMoveKeepOriginal: Bool = false

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingGroup: M2Group?
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?
    @State private var isBulkMoveMode = false
    @State private var selectedBulkItemIDs: Set<M3Item.ID> = []
    @State private var isShowingBulkMoveSheet = false
    @State private var selectedMovePackID = ""
    @State private var selectedMoveGroupID = ""
    @State private var keepSourceItems = false
    @State private var moveInsertPosition: ItemEditView.MoveInsertPosition = .end
    @State private var scrollTargetItemID: M3Item.ID?
    @State private var scrollTargetItemAnchor: UnitPoint = .bottom

    /// DBからソートして取得する（group.child は.order昇順）
    private var sortedItems: [M3Item] {
        group.child.sorted { $0.order < $1.order }
    }

    private var rowHeight: CGFloat { appRowHeight(fontScale) }
    /// order順のPackリストを返す
    private var sortedPacks: [M1Pack] {
        packs.sorted { $0.order < $1.order }
    }
    /// まとめて移動の対象を表示順で返す
    private var selectedBulkItems: [M3Item] {
        sortedItems.filter { selectedBulkItemIDs.contains($0.id) }
    }
    /// まとめて移動の移動先Pack
    private var selectedMovePack: M1Pack? {
        sortedPacks.first(where: { $0.id == selectedMovePackID })
    }
    /// まとめて移動の移動先Group
    private var selectedDestinationGroup: M2Group? {
        guard let pack = selectedMovePack else { return nil }
        return pack.child.sorted { $0.order < $1.order }
            .first(where: { $0.id == selectedMoveGroupID })
    }
    private var hasBulkSelection: Bool { !selectedBulkItems.isEmpty }
    // 説明文表示判定をまとめておく
    private var isBeginnerMode: Bool { displayMode == .beginner }
    // ヘッダーの高さを表示モードで変える
    private var headerHeight: CGFloat {
        // 初心者ヘルプを欠けさせないよう、文字サイズに応じてヘッダーを高くする
        isBeginnerMode ? appHeaderHeightForBeginner(fontScale) : appHeaderHeightForExpert(fontScale)
    }

    // Group編集はシートへ移行したが、アイテムのクイック編集は引き続きPopupを利用
    // そのため、どちらかが表示されている間はナビバーボタンを非活性にする
    private var isShowingPopup: Bool { editingGroup != nil || editingItem != nil }

    private var bulkMoveSheetHeight: CGFloat {
        switch fontScale {
        case .large:
            return 540
        case .xLarge:
            return 620
        default:
            return 440
        }
    }

    var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                List {
                    Section {
                        ForEach(sortedItems) { item in
                            NavigationLink(
                                value: AppDestination.itemEdit(
                                    packID: pack.id,
                                    groupID: group.id,
                                    itemID: item.id,
                                    sort: nil
                                )
                            ) {
                                ItemRowView(
                                    item: item,
                                    isBulkMoveMode: isBulkMoveMode,
                                    isBulkMoveSelected: selectedBulkItemIDs.contains(item.id)
                                ) { selected, point in
                                    editingItem = selected
                                    popupAnchor = point
                                } onToggleBulkMoveSelection: {
                                    toggleBulkMoveSelection(item)
                                }
                            }
                            .id(item.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(COLOR_ROW_BACK)
                        }
                        .onMove(perform: moveItem)

                        AppendAtEndRowView(systemImage: "plus.circle",
                                           fontScale: fontScale,
                                           showsText: isBeginnerMode) {
                            addItemAtEndAndNavigate()
                        }
                        .disabled(isBulkMoveMode)
                        .opacity(isBulkMoveMode ? 0.45 : 1.0)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(COLOR_ROW_BACK)
                        // 高さは AppendAtEndRowView 内側の padding(.vertical, 8) で自動調整される
                        .environment(\.defaultMinListRowHeight, 0)
                    } header: {
                        GroupRowView(group: group, isHeader: true) { selected, _ in
                            editingGroup = selected
                            // Groupシートでは座標を使わないため、その都度リセットする
                            popupAnchor = nil
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingGroup = group
                            popupAnchor = nil
                        }
                        .background(COLOR_ROW_GROUP)
                        .cornerRadius(16)
                        .padding(.top, -20) // 上余白を減らす
                    } footer: {
                        if isBeginnerMode {
                            // 初心者モードでは操作説明をフッターに表示して迷いを減らす
                            FooterView()
                                .listRowSeparator(.hidden) // 下線なし
                        }
                    }
                }
                .listStyle(.plain)
                // スクロール位置表示は全画面で出さない
                .scrollIndicators(.hidden)
                .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
                .padding(.horizontal, 8)
                .environment(\.defaultMinListRowHeight,
                             rowTextLines.usesExtraSmallItemRow
                                ? appExtraSmallRowHeight(fontScale)
                                : appRowHeight(fontScale))
                .navigationBarBackButtonHidden(true)
                .onChange(of: scrollTargetItemID) { _, _ in
                    scrollToNewItemIfReady(scrollProxy)
                }
                .onChange(of: sortedItems.map(\.id)) { _, _ in
                    scrollToNewItemIfReady(scrollProxy)
                }
            }
            .safeAreaInset(edge: .top) {
                // PackListViewと同じようにカスタムヘッダーへボタンを移設し、タイトルを下段に分離
                // 中央寄せのタイトルで、左右の操作ボタンに目を移した後でも視線を戻しやすくする
                // spacingを詰めてヘッダーの上下余白を約半分に抑える
                VStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 0) {
                        // 戻るボタンと初心者向け説明
                        VStack(spacing: 6) {
                            Button {
                                dismiss()
                                // GroupListView.onAppearで.save()が呼ばれる
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isShowingPopup)

                            if isBeginnerMode {
                                Text("back.groups")
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
                            Text("item.list")
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

                        // 新しいアイテム追加と説明
                        VStack(spacing: 6) {
                            Button(action: addItem) {
                                Image(systemName: "plus.circle")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(COLOR_ADD_ACTION)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isShowingPopup)

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
                    }

                    // パック＞グループのパンくずを並べ、各名称は画面幅の1/4までで自動省略する
                    BreadcrumbView(
                        packName: pack.name.placeholder("new.pack"),
                        groupName: group.name.placeholder("new.group"),
                        itemName: nil,
                        rootAction: { navigationStore.path = NavigationPath() },
                        packAction: { navigationStore.path = NavigationPath([AppDestination.groupList(packID: pack.id)]) },
                        groupAction: { navigationStore.path = NavigationPath([AppDestination.groupList(packID: pack.id), AppDestination.itemList(packID: pack.id, groupID: group.id)]) },
                        itemAction: nil
                    )
                }
                // iPadマルチウィンドウ時の左上システムアイコンに隠れないよう、ヘッダー全体を右へずらす
                .padding(.leading, ipadWindowControlInset())
                .tint(.primary)
                .frame(height: headerHeight)
                .padding(.horizontal, 16)
                // ヘッダーの上下余白を抑えてリスト領域を広げる
                .padding(.vertical, 3)
                .background(.thinMaterial)
                // 初心者ヘルプ・タイトル・パンくずを「大」までで頭打ち
                .cappedAtLargeFontSize()
            }
            .safeAreaInset(edge: .bottom) {
                bulkMoveFooter
            }
            .onAppear {
                updateUndoRedo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }

            //----------------------------------
            //(ZStack 1) Popupで表示
            //----------------------------------
            //(ZStack 1) Popupで表示
            if let item = editingItem {
                PopupView(anchor: popupAnchor) {
                    //.onDismiss：PopupView内から閉じる場合
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
                        if editingGroup != nil {
                            editingGroup = nil
                            popupAnchor = nil
                        }
                        return
                    }

                    if horizontal <= 80 || abs(vertical) >= 50 { return }
                    dismiss()
                }
        )
        // Group編集用のシートを追加
        .sheet(item: $editingGroup, onDismiss: {
            // onDismissで座標情報をリセットしておく
            popupAnchor = nil
        }) { group in
            GroupEditView(group: group)
                .appFontScale(fontScale)
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $isShowingBulkMoveSheet) {
            // 既存のアイテム移動シートをまとめて移動でも使う
            ItemMoveSheetView(
                packs: sortedPacks,
                itemName: String(localized: "bulk.move"),
                fontScale: fontScale,
                selectedPackID: $selectedMovePackID,
                selectedGroupID: $selectedMoveGroupID,
                keepOriginal: $keepSourceItems,
                insertPosition: $moveInsertPosition,
                disableConfirm: selectedDestinationGroup == nil || selectedBulkItems.isEmpty,
                onConfirm: handleBulkMoveConfirmation,
                onCancel: { isShowingBulkMoveSheet = false }
            )
            .appFontScale(fontScale)
            .presentationDetents([.height(bulkMoveSheetHeight)])
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .onChange(of: selectedMovePackID) { _, _ in
            if isShowingBulkMoveSheet {
                syncBulkMoveGroupSelection(useStoredPreference: false)
            }
        }
    }

    /// まとめて移動用の下部フッター
    @ViewBuilder
    private var bulkMoveFooter: some View {
        VStack(spacing: 0) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
                .ignoresSafeArea(edges: .horizontal)

            if isBulkMoveMode {
                HStack(spacing: 10) {
                    Button("cancel") {
                        cancelBulkMoveMode()
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 4) {
                        Image(systemName: "circle")
                            .imageScale(.large)
                            .foregroundStyle(.orange)

                        Text("bulk.move.instructions")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                    }
                    // 文頭のオレンジ丸アイコンでセル先頭の選択ボタンを示す
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("move") {
                        // まとめて移動シートを開いた頻度と選択数を集計する
                        GALogger.log(.feature_use(name: "bulk_move", source: "item_list_footer", detail: "open"))
                        prepareBulkMoveSheet()
                        isShowingBulkMoveSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasBulkSelection)
                }
                .padding(.horizontal, 16)
                // フッターの高さを抑えるため、ボタン外側の余白は最小にする
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
            } else {
                Button {
                    // まとめて移動モードの開始頻度を集計する
                    GALogger.log(.feature_use(name: "bulk_move", source: "item_list_footer", detail: "start"))
                    beginBulkMoveMode()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("bulk.move")
                    }
                    // 開始ボタンも選択時と同じオレンジ丸チェックで統一する
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(0.75))
                )
                .padding(.horizontal, 16)
                // フッターの高さを抑えるため、ボタン外側の余白は最小にする
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
            }
        }
        // フッターの操作文は「大」までで頭打ちし、ボタン欠けを抑える
        .cappedAtLargeFontSize()
    }

    /// フッター：ボタンの説明
    struct FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("item.status.unchecked.first")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .imageScale(.large)
                        Text("lacking")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.circle")
                            .imageScale(.large)
                        Text("enough")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .imageScale(.large)
                        Text("checked.regardless.count")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .imageScale(.large)
                        Text("not.needed")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            }
            .padding(.top, 20)
            .padding(.leading, 30)
            .padding(.trailing, 8)
            // 初心者ヘルプ「アイテムの状態」を「大」までで頭打ち
            .cappedAtLargeFontSize()
        }
    }


    /// まとめて移動モードを開始する
    private func beginBulkMoveMode() {
        editingGroup = nil
        editingItem = nil
        popupAnchor = nil
        selectedBulkItemIDs.removeAll()
        isBulkMoveMode = true
    }

    /// まとめて移動モードを中止する
    private func cancelBulkMoveMode() {
        selectedBulkItemIDs.removeAll()
        isBulkMoveMode = false
    }

    /// まとめて移動対象の選択を切り替える
    private func toggleBulkMoveSelection(_ item: M3Item) {
        if selectedBulkItemIDs.contains(item.id) {
            selectedBulkItemIDs.remove(item.id)
        } else {
            selectedBulkItemIDs.insert(item.id)
        }
    }

    /// まとめて移動シートの初期値を準備する
    private func prepareBulkMoveSheet() {
        keepSourceItems = lastMoveKeepOriginal
        if let storedInsertPosition = ItemEditView.MoveInsertPosition(rawValue: lastMoveInsertPositionRawValue) {
            moveInsertPosition = storedInsertPosition
        } else {
            moveInsertPosition = .end
        }

        if let storedPack = sortedPacks.first(where: { $0.id == lastMovePackID }) {
            selectedMovePackID = storedPack.id
        } else if sortedPacks.contains(where: { $0.id == pack.id }) {
            selectedMovePackID = pack.id
        } else if let firstPack = sortedPacks.first {
            selectedMovePackID = firstPack.id
        } else {
            selectedMovePackID = ""
        }

        syncBulkMoveGroupSelection(useStoredPreference: true)
    }

    /// Pack選択に合わせて移動先Groupを補正する
    private func syncBulkMoveGroupSelection(useStoredPreference: Bool) {
        guard let pack = selectedMovePack else {
            selectedMoveGroupID = ""
            return
        }

        let groups = pack.child.sorted { $0.order < $1.order }

        if useStoredPreference,
           let storedGroup = groups.first(where: { $0.id == lastMoveGroupID }) {
            selectedMoveGroupID = storedGroup.id
            return
        }

        if let currentSelection = groups.first(where: { $0.id == selectedMoveGroupID }) {
            selectedMoveGroupID = currentSelection.id
            return
        }

        if pack.id == group.parent?.id,
           let currentGroup = groups.first(where: { $0.id == group.id }) {
            selectedMoveGroupID = currentGroup.id
            return
        }

        if let firstGroup = groups.first {
            selectedMoveGroupID = firstGroup.id
        } else {
            selectedMoveGroupID = ""
        }
    }

    /// まとめて移動シートの確定処理
    private func handleBulkMoveConfirmation() {
        guard let destinationGroup = selectedDestinationGroup else { return }

        // まとめて移動の操作傾向を件数だけで集計する
        GALogger.log(.operation(name: keepSourceItems ? "copy" : "move",
                                target: "item",
                                source: "bulk_move",
                                detail: moveInsertPosition.rawValue,
                                count: selectedBulkItemIDs.count))
        performBulkMoveOrCopy(to: destinationGroup, copy: keepSourceItems)
        lastMovePackID = selectedMovePackID
        lastMoveGroupID = destinationGroup.id
        lastMoveInsertPositionRawValue = moveInsertPosition.rawValue
        lastMoveKeepOriginal = keepSourceItems
        isShowingBulkMoveSheet = false
        isBulkMoveMode = false
        selectedBulkItemIDs.removeAll()
    }

    /// 選択した複数アイテムを移動または複製する
    private func performBulkMoveOrCopy(to destinationGroup: M2Group, copy: Bool) {
        let movingItems = selectedBulkItems
        guard !movingItems.isEmpty else { return }

        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        let movingIDs = Set(movingItems.map(\.id))
        var destinationItems = destinationGroup.child.sorted { $0.order < $1.order }
        if !copy {
            // 同一Group内の並べ替えでも重複しないよう、移動対象を一度抜く
            destinationItems.removeAll { movingIDs.contains($0.id) }
        }

        let insertIndex: Int
        switch moveInsertPosition {
        case .start:
            insertIndex = 0
        case .end:
            insertIndex = destinationItems.count
        }
        let clampedIndex = max(0, min(insertIndex, destinationItems.count))

        let insertedItems = movingItems.map { sourceItem in
            if copy {
                let newItem = M3Item(name: sourceItem.name,
                                     memo: sourceItem.memo,
                                     stock: sourceItem.stock,
                                     need: sourceItem.need,
                                     weight: sourceItem.weight,
                                     order: sourceItem.order,
                                     parent: destinationGroup)
                modelContext.insert(newItem)
                return newItem
            } else {
                sourceItem.parent = destinationGroup
                return sourceItem
            }
        }

        destinationItems.insert(contentsOf: insertedItems, at: clampedIndex)
        let endIndex = clampedIndex + insertedItems.count - 1
        assignSparseOrders(nodes: destinationItems, range: clampedIndex...endIndex) {
            // order のみを整え、child 配列を並べ替えない
            normalizeSparseOrders(destinationItems)
        }
    }

    /// アイテム追加
    func addItem() {
        // 新規追加の位置設定ごとの利用頻度を匿名で集計する
        GALogger.log(.operation(name: "add", target: "item", source: "header", detail: insertionPosition.rawValue, count: nil))
        var newItemID: M3Item.ID?
        let scrollAnchor: UnitPoint = insertionPosition == .head ? .top : .bottom

        // 履歴サービスを利用して新規追加を1つのアクションとして記録する
        history.perform(context: modelContext) {
            let items = sortedItems
            let insertionIndex: Int = {
                switch insertionPosition {
                    case .head:
                        return 0
                    case .tail:
                        return items.count
                }
            }()
            
            let newOrder = sparseOrderForInsertion(items: items, index: insertionIndex) {
                // order のみを整え、child 配列を並べ替えない
                normalizeSparseOrders(items)
            }
            // 新しいアイテム
            let newItem = M3Item(name: "",
                                 order: newOrder,
                                 parent: group)
            // DB追加
            modelContext.insert(newItem)
            // child 配列はそのままにしておき、表示側で order ソートする
            newItemID = newItem.id
        }

        popupAnchor = nil
        scrollTargetItemAnchor = scrollAnchor
        // 新規Itemが見える位置までスクロールする
        scrollTargetItemID = newItemID
    }

    /// 末尾追加セル用：常に末尾へ追加して編集画面へ遷移する
    private func addItemAtEndAndNavigate() {
        // 末尾追加専用セルの利用頻度を集計する
        GALogger.log(.operation(name: "add", target: "item", source: "append_end_row", detail: "tail", count: nil))
        var newItem: M3Item?

        history.perform(context: modelContext) {
            let items = sortedItems
            let newOrder = sparseOrderForInsertion(items: items, index: items.count) {
                // order のみを整え、child 配列を並べ替えない
                normalizeSparseOrders(items)
            }

            let item = M3Item(name: "",
                              order: newOrder,
                              parent: group)
            modelContext.insert(item)
            newItem = item
        }

        popupAnchor = nil
        if let newItem {
            scrollTargetItemAnchor = .bottom
            scrollTargetItemID = newItem.id
            navigationStore.path.append(
                AppDestination.itemEdit(
                    packID: pack.id,
                    groupID: group.id,
                    itemID: newItem.id,
                    sort: nil
                )
            )
        }
    }

    /// 新規ItemがListに反映されてからスクロールする
    private func scrollToNewItemIfReady(_ scrollProxy: ScrollViewProxy) {
        guard let itemID = scrollTargetItemID,
              sortedItems.contains(where: { $0.id == itemID }) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                scrollProxy.scrollTo(itemID, anchor: scrollTargetItemAnchor)
            }
            scrollTargetItemID = nil
        }
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

    /// Drag-Drop-Move
    private func moveItem(from source: IndexSet, to destination: Int) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        var items = sortedItems
        let movedIDs = Set(source.map { sortedItems[$0].id })
        items.move(fromOffsets: source, toOffset: destination)

        var index = 0
        while index < items.count {
            if movedIDs.contains(items[index].id) {
                var end = index
                while end + 1 < items.count, movedIDs.contains(items[end + 1].id) {
                    end += 1
                }
                assignSparseOrders(nodes: items, range: index...end) {
                    // order の整合性を保つだけで child を並べ替えない
                    normalizeSparseOrders(items)
                }
                index = end + 1
            } else {
                index += 1
            }
        }
        // order の更新のみで十分。List は order でソートして再描画される。
    }
}


#Preview {
    let pack = M1Pack(name: "", order: 0)
    let group = M2Group(name: "", order: 0, parent: pack)
    pack.child.append(group)
    return ItemListView(pack: pack, group: group)
}
