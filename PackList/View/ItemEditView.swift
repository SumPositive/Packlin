//  アイテム編集画面
//  名称、メモ、数量、移動、複製、前後移動をまとめる
//

import SwiftUI
import SwiftData
import UIKit
import AZDial

private enum PacklinDialSettings {
    static let styleKey = "packlin.dialStyle"
    static let tuningKey = "packlin.dialTuning"
    static let defaultTuning = AZDialInteractionTuningPreset.mild.tuning

    static func loadTuning(from data: Data) -> AZDialInteractionTuning {
        guard !data.isEmpty,
              let tuning = try? JSONDecoder().decode(AZDialInteractionTuning.self, from: data) else {
            // 未設定時の感度は「控えめ」を既定値にする
            return defaultTuning
        }
        return tuning
    }

    static func encodeTuning(_ tuning: AZDialInteractionTuning) -> Data {
        (try? JSONEncoder().encode(tuning)) ?? Data()
    }
}

/// 画面遷移用のアイテム編集ビュー
struct ItemEditView: View {
    let pack: M1Pack
    let group: M2Group
    @Bindable var item: M3Item
    let onDismiss: () -> Void
    let onSelectItem: (M3Item) -> Void
    let adjacentItemProvider: ((M3Item, Int) -> M3Item?)?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var history: UndoStackService
    @EnvironmentObject private var navigationStore: NavigationStore

    @State private var focusedField: Field?
    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]
    // PackListViewと同じ表示モードを共有し、初心者向け説明の表示を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    // 不揮発保存
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock
    @AppStorage(AppStorageKey.linkCheckOffWithZero) private var linkCheckOffWithZero: Bool = DEF_linkCheckOffWithZero
    // 不揮発保存：itemEdit.move用
    @AppStorage("itemEdit.move.lastPackID") private var lastMovePackID: String = ""
    @AppStorage("itemEdit.move.lastGroupID") private var lastMoveGroupID: String = ""
    @AppStorage("itemEdit.move.lastInsertPosition") private var lastMoveInsertPositionRawValue: String = MoveInsertPosition.end.rawValue
    @AppStorage("itemEdit.move.lastKeepOriginal") private var lastMoveKeepOriginal: Bool = false

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var isShowingMoveSheet = false
    @State private var selectedPackID: String
    @State private var selectedGroupID: String
    @State private var keepSourceItem = false
    @State private var moveInsertPosition: MoveInsertPosition = .end
    @State private var isDraggingInsideQuantitySection = false
    @State private var isShowingDialSettings = false

    /// === Fix 7: Undo グループ開閉のバランス保証フラグ ===
    /// onAppear / onDisappear は NavigationStack の遷移や iOS のシート再描画で
    /// 必ずしも 1:1 に呼ばれない。アンバランスになると UndoStackService の
    /// transactionDepth が破綻して、それ以降の操作が履歴に記録されなくなる。
    /// このフラグで「begin したかどうか」を覚えておき、end は対応する begin が
    /// あった場合のみ呼ぶ（再入時の二重 begin / 不対応 end を防止）。
    @State private var isUndoGroupingActive: Bool = false

    @AppStorage(PacklinDialSettings.styleKey) private var dialStyleID = DialStyle.shape.id
    @AppStorage(PacklinDialSettings.tuningKey) private var dialTuningData = Data()

    private let sectionCornerRadius: CGFloat = 12

    /// アクションボタンの理想幅
    private var idealActionButtonWidth: CGFloat {
        switch fontScale {
        case .system, .standard:
            return 90
        case .large, .xLarge:
            return 100
        }
    }

    private func actionButtonWidth(for availableWidth: CGFloat) -> CGFloat {
        // 4列ボタンが画面幅を超えないよう、実表示幅から1ボタン幅を逆算する
        let fittedWidth = (availableWidth - actionButtonSpacing * 3) / 4
        return min(idealActionButtonWidth, max(58, fittedWidth))
    }

    private func actionButtonContent(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .fixedSize()
            Text(title)
                // 狭い端末では文字だけ縮小し、アイコンサイズは維持する
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
        }
        // ボタン枠に文字が張り付かないよう、内容側に最小余白を持たせる
        .padding(.horizontal, 2)
    }

    private var contentHorizontalPadding: CGFloat {
        switch fontScale {
        case .large, .xLarge:
            // 大きい文字でも他画面と揃うよう左右に8pt残す
            return 8
        default:
            return 20
        }
    }

    private var actionButtonSpacing: CGFloat {
        switch fontScale {
        case .large, .xLarge:
            // 大きい文字ではボタン間隔を詰めて横欠けを防ぐ
            return 6
        default:
            return 6
        }
    }

    private var headerHorizontalPadding: CGFloat {
        switch fontScale {
        case .large, .xLarge:
            // ヘッダーも大きい文字では本文と同じ余白に揃える
            return 8
        default:
            return 16
        }
    }

    private var dialSettingsFontScale: FontScale {
        switch fontScale {
        case .xLarge:
            // AZDial設定は横幅固定のプリセットがあるため「特大」を「大」に丸める
            return .large
        default:
            return fontScale
        }
    }

    private var isBeginnerMode: Bool { displayMode == .beginner }
    // ヘッダーの高さを表示モードで変える
    private var headerHeight: CGFloat {
        // 初心者ヘルプを欠けさせないよう、文字サイズに応じてヘッダーを高くする
        isBeginnerMode ? appHeaderHeightForBeginner(fontScale) : appHeaderHeightForExpert(fontScale)
    }

//    private var nameFieldMinHeight: CGFloat {
//        UIFont.preferredFont(forTextStyle: .title2).lineHeight * 2 + 16
//    }

    private var canSelectPreviousItem: Bool {
        adjacentItem(offset: -1) != nil
    }

    private var canSelectNextItem: Bool {
        adjacentItem(offset: 1) != nil
    }
    
    private enum Field: Hashable {
        case name
        case memo
    }

    private func focusBinding(for field: Field) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { newValue in
                if newValue {
                    focusedField = field
                } else if focusedField == field {
                    focusedField = nil
                }
            }
        )
    }

    enum MoveInsertPosition: String, CaseIterable, Identifiable {
        case start
        case end

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .start:
                return "top.group"
            case .end:
                return "bottom.group"
            }
        }
    }

    init(pack: M1Pack,
         group: M2Group,
         item: M3Item,
         onDismiss: @escaping () -> Void,
         onSelectItem: @escaping (M3Item) -> Void,
         adjacentItemProvider: ((M3Item, Int) -> M3Item?)? = nil) {
        self.pack = pack
        self.group = group
        self._item = Bindable(item)
        self.onDismiss = onDismiss
        self.onSelectItem = onSelectItem
        self.adjacentItemProvider = adjacentItemProvider
        self._selectedPackID = State(initialValue: pack.id)
        self._selectedGroupID = State(initialValue: group.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                //    // 見出し
                //    VStack(alignment: .leading, spacing: 4) {
                //        // パック名 表示
                //        pack.name.placeholderText("新しいパック")
                //            .font(.caption)
                //            .foregroundStyle(.secondary)
                //        // グループ名 表示
                //        group.name.placeholderText("新しいグループ")
                //            .font(.headline)
                //    }
                // 操作
                EditorSection(title: "actions") {
                    GeometryReader { proxy in
                        let buttonWidth = actionButtonWidth(for: proxy.size.width)
                        VStack {
                            HStack(spacing: actionButtonSpacing) {
                                // 上・前へ
                                Button {
                                    // (-1) 1つ前のアイテムを編集対象に切り替える
                                    selectAdjacentItem(by: -1)
                                } label: {
                                    actionButtonContent("back", systemImage: "arrow.up.circle")
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accessibilityLabel(Text("back"))
                                .disabled(!canSelectPreviousItem)

                                // 先頭に追加
                                Button {
                                    addItemEdit(at: .head)
                                } label: {
                                    actionButtonContent("top", systemImage: "plus.circle")
                                        .foregroundStyle(COLOR_ADD_ACTION)
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accessibilityLabel(Text("top"))
                            
                                // 複製
                                Button {
                                    item.duplicate()
                                    onDismiss()
                                } label: {
                                    actionButtonContent("copy", systemImage: "plus.square.on.square")
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accessibilityLabel(Text("copy"))
                            
                                // 削除
                                Button(role: .destructive) {
                                    item.delete()
                                    onDismiss()
                                } label: {
                                    actionButtonContent("delete", systemImage: "trash")
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accessibilityLabel(Text("delete"))
                            }
                            // 2段目
                            HStack(spacing: actionButtonSpacing) {
                                // 下・次へ
                                Button {
                                    // (+1) 1つ次のアイテムを編集対象に切り替える
                                    selectAdjacentItem(by: 1)
                                } label: {
                                    actionButtonContent("next", systemImage: "arrow.down.circle")
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accessibilityLabel(Text("next"))
                                .disabled(!canSelectNextItem)

                                // 末尾に追加
                                Button {
                                    addItemEdit(at: .tail)
                                } label: {
                                    actionButtonContent("bottom", systemImage: "plus.circle")
                                        .foregroundStyle(COLOR_ADD_ACTION)
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accessibilityLabel(Text("bottom"))

                                // 移動
                                Button {
                                    prepareMoveSheet()
                                    isShowingMoveSheet = true
                                } label: {
                                    actionButtonContent("move", systemImage: "hand.point.up.left.and.text")
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accessibilityLabel(Text("move"))

                                // 消す
                                Button(role: .destructive) {
                                    // アイテムを初期値にリセット
                                    resetItemToInitialState()
                                } label: {
                                    actionButtonContent("erase", systemImage: "eraser")
                                        .frame(width: buttonWidth, height: 44)
                                        .background(COLOR_BACK_INPUT)
                                        .clipShape(RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: sectionCornerRadius, style: .continuous)
                                                .strokeBorder(COLOR_BACK_POPUP, lineWidth: 1)
                                        )
                                }
                                .accentColor(Color(.systemPink))
                                .accessibilityLabel(Text("erase"))
                            }
                        }
                        .frame(width: proxy.size.width, alignment: .leading)
                    }
                    .frame(height: 100)
                    // 固定枠ボタンの文字が欠けないよう「大」までで頭打ち
                    .cappedAtLargeFontSize()
                }
                // 名称
                EditorSection(title: "name") {
                    PacklinMemoEditor(
                        placeholder: "new.item",
                        text: $item.name,
                        isFocused: focusBinding(for: .name),
                        minHeight: 64,
                        maxLength: APP_MAX_NAME_LEN,
                        backgroundColor: COLOR_BACK_INPUT,
                        cornerRadius: sectionCornerRadius
                    )
                }
                // メモ
                EditorSection(title: "memo") {
                    PacklinMemoEditor(
                        placeholder: nil,
                        text: $item.memo,
                        isFocused: focusBinding(for: .memo),
                        minHeight: 64,
                        maxLength: APP_MAX_MEMO_LEN,
                        backgroundColor: COLOR_BACK_INPUT,
                        cornerRadius: sectionCornerRadius
                    )
                }

                // 数量
                EditorSection {
                    HStack(spacing: 8) {
                        // 数量
                        Text("quantity")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        quantityCheckButton
                    }
                    ItemQuantityEditor(item: item)
                    HStack {
                        Spacer()
                        Button {
                            isShowingDialSettings = true
                        } label: {
                            Label("item.quantity.dialSettings", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                    // 必要数ダイアルの下に余白を作って設定ボタンを置く
                    .padding(.top, 30)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            isDraggingInsideQuantitySection = true
                        }
                        .onEnded { _ in
                            isDraggingInsideQuantitySection = false
                        }
                )
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.vertical, 12)
        }
        // スクロール位置表示は全画面で出さない
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(COLOR_ROW_GROUP)
        //.navigationTitle("アイテム編集")
        .navigationBarBackButtonHidden(true)
        //.navigationBarTitleDisplayMode(.inline)
        //.toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            // 編集画面でもPackListView風のヘッダーを共通化し、タイトルを下段へ移動
            // 中央揃えのタイトルで、長い名称でも視線が中央に集まり読みやすくなるようにする
            // spacingを詰めて上下の余白を半分程度に抑え、編集領域を広く確保する
            VStack(alignment: .center, spacing: 6) {
                HStack(spacing: 0) {
                    // 戻る＋説明
                    VStack(spacing: 6) {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "chevron.backward")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.borderless)

                        if isBeginnerMode {
                            Text("back.items")
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

                    // Undo＋説明
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
                        .disabled(!canUndo)

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
                        Text("item.edit")
                            .font(.system(size: 15))
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .frame(minWidth: 50)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    
                    // Redo＋説明
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
                        .disabled(!canRedo)

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

                    // 追加＋説明
                    VStack(spacing: 6) {
                        Button {
                            addItemEdit()
                        } label: {
                            Image(systemName: "plus.circle")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(COLOR_ADD_ACTION)
                        }
                        .buttonStyle(.borderless)

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

                // パック＞グループ＞アイテムのパンくずを並べ、各名称は画面幅の1/4までに抑える
                BreadcrumbView(
                    packName: pack.name.placeholder("new.pack"),
                    groupName: group.name.placeholder("new.group"),
                    itemName: item.name.placeholder("new.item"),
                    rootAction: { navigationStore.path = NavigationPath() },
                    packAction: { navigationStore.path = NavigationPath([AppDestination.groupList(packID: pack.id)]) },
                    groupAction: { navigationStore.path = NavigationPath([AppDestination.groupList(packID: pack.id), AppDestination.itemList(packID: pack.id, groupID: group.id)]) },
                    itemAction: nil
                )
            }
            // iPadマルチウィンドウ時の左上システムアイコンに隠れないよう、ヘッダー全体を右へ寄せる
            .padding(.leading, ipadWindowControlInset())
            .tint(.primary)
            .frame(height: headerHeight)
            .padding(.horizontal, headerHorizontalPadding)
            // ヘッダーの上下余白を控えめにして編集フォームを広く見せる
            .padding(.vertical, 3)
            .background(.thinMaterial)
            // 初心者ヘルプ・タイトル・パンくずを「大」までで頭打ち
            .cappedAtLargeFontSize()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    if !(horizontal <= 80 || abs(vertical) >= abs(horizontal)) {
                        guard !isDraggingInsideQuantitySection else {
                            // ダイアル範囲を除外して閉じられないようにする
                            return
                        }
                        // 右へスワイプしたときに閉じる
                        onDismiss()
                    }
                    else if vertical < -20, abs(horizontal) < abs(vertical) {
                        // 下へスワイプ時、キーボードを隠す
                        dismissKeyboard()
                    }
                }
        )
        .onAppear {
            // === Fix 7: lifecycle 不均衡対策 ===
            // 二重 onAppear（戻り遷移時など）を考慮し、未開始のときだけ begin する
            beginUndoGroupingIfNeeded()
            focusNameIfEmpty()
        }
        .onDisappear {
            // === Fix 7: lifecycle 不均衡対策 ===
            // Trim：末尾の空白・改行を正規化
            item.name = item.name.trimTrailSpacesAndNewlines
            item.memo = item.memo.trimTrailSpacesAndNewlines
            // チェックと在庫数を連動させる
            if linkCheckWithStock {
                item.check = (0 < item.need && item.need <= item.stock)
            }
            // begin したときだけ end する。transactionDepth の破綻を防ぐ
            endUndoGroupingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
            updateUndoRedo()
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            // 移動 設定シート
            ItemMoveSheetView(
                packs: sortedPacks,
                itemName: item.name,
                fontScale: fontScale,
                selectedPackID: $selectedPackID,
                selectedGroupID: $selectedGroupID,
                keepOriginal: $keepSourceItem,
                insertPosition: $moveInsertPosition,
                disableConfirm: selectedDestinationGroup == nil,
                onConfirm: handleMoveConfirmation,
                onCancel: { isShowingMoveSheet = false }
            )
            .appFontScale(fontScale)
            .presentationDetents([.height(moveSheetHeight)])
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $isShowingDialSettings) {
            NavigationStack {
                AZDialSettingsView(
                    tuning: dialTuningBinding,
                    style: dialStyleBinding
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("done") {
                            isShowingDialSettings = false
                        }
                    }
                }
            }
            // AZDial設定はプリセットボタンの文字欠けを防ぐため「大」までで頭打ち
            .cappedAtLargeFontSize()
            .appFontScale(dialSettingsFontScale)
        }
        .onChange(of: selectedPackID) { _, _ in
            guard isShowingMoveSheet else { return }
            syncGroupSelection(useStoredPreference: false)
        }
        .onChange(of: item.id) { _, _ in
            focusNameIfEmpty()
        }
    }

    private var moveSheetHeight: CGFloat {
        switch fontScale {
        case .large:
            return 540
        case .xLarge:
            return 620
        default:
            return 440
        }
    }

    /// === Fix 7: Undo グループの安全な開始 ===
    /// `isUndoGroupingActive` フラグで再入を防止する。既に開いていれば何もしない。
    /// onAppear が複数回呼ばれた場合でも、グルーピングは 1 回だけ開始される。
    private func beginUndoGroupingIfNeeded() {
        guard !isUndoGroupingActive else { return }
        modelContext.undoManager?.groupingBegin()
        isUndoGroupingActive = true
    }

    /// === Fix 7: Undo グループの安全な終了 ===
    /// `isUndoGroupingActive` が立っているときだけ end を呼ぶ。
    /// onAppear なしの onDisappear や二重 onDisappear で transactionDepth が
    /// 負方向に進むのを防ぐ。
    private func endUndoGroupingIfNeeded() {
        guard isUndoGroupingActive else { return }
        modelContext.undoManager?.groupingEnd()
        isUndoGroupingActive = false
    }

    private func focusNameIfEmpty() {
        guard item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // 画面遷移直後はTextEditorの生成が遅れるため、表示確定後にNameへフォーカスする
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focusedField = .name
            }
        }
    }

    /// アイテム追加し、そのアイテムを編集状態にする
    private func addItemEdit() {
        addItemEdit(at: insertionPosition)
    }

    /// 指定位置にアイテムを追加し、そのアイテムを編集状態にする
    private func addItemEdit(at position: InsertionPosition) {
        // 履歴サービスを利用して新規追加を1つのアクションとして記録する
        history.perform(context: modelContext) {
            let items = group.child.sorted { $0.order < $1.order }
            let insertionIndex: Int = {
                switch position {
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
            // ReOrder 不要
            
            // 新しいアイテムを編集対象にする
            withAnimation {
                onSelectItem(newItem)
            }
        }
    }
    
    /// 現在のアイテムを初期値にリセットする
    private func resetItemToInitialState() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        // 初期値をセット
        item.name = ""
        item.memo = ""
        item.check = false
        item.stock = 0
        item.need = 1
        item.weight = 0
        // フォーカスを.nameへ
        //focusedField = .name
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
        // （PackListView/GroupListView は元から history.canUndo を直接見ているため
        //  この問題は発生していなかった）
        if let um = modelContext.undoManager {
            canUndo = um.canUndo
            canRedo = um.canRedo
        } else {
            canUndo = false
            canRedo = false
        }
    }
    /// order順のPackリストを返す
    private var sortedPacks: [M1Pack] {
        packs.sorted { $0.order < $1.order }
    }
    /// selectedPackIDのPackを返す
    private var selectedPack: M1Pack? {
        sortedPacks.first(where: { $0.id == selectedPackID })
    }

    private var selectedDestinationGroup: M2Group? {
        guard let pack = selectedPack else { return nil }
        return pack.child.sorted { $0.order < $1.order }
            .first(where: { $0.id == selectedGroupID })
    }

    /// 移動　シート
    private func prepareMoveSheet() {
        keepSourceItem = lastMoveKeepOriginal
        if let storedInsertPosition = MoveInsertPosition(rawValue: lastMoveInsertPositionRawValue) {
            moveInsertPosition = storedInsertPosition
        } else {
            moveInsertPosition = .end
        }

        if let storedPack = sortedPacks.first(where: { $0.id == lastMovePackID }) {
            selectedPackID = storedPack.id
        } else if sortedPacks.contains(where: { $0.id == pack.id }) {
            selectedPackID = pack.id
        } else if let firstPack = sortedPacks.first {
            selectedPackID = firstPack.id
        } else {
            selectedPackID = ""
        }

        syncGroupSelection(useStoredPreference: true)
    }

    private func syncGroupSelection(useStoredPreference: Bool) {
        guard let pack = selectedPack else {
            selectedGroupID = ""
            return
        }

        let groups = pack.child.sorted { $0.order < $1.order }

        if useStoredPreference,
           let storedGroup = groups.first(where: { $0.id == lastMoveGroupID }) {
            selectedGroupID = storedGroup.id
            return
        }

        if let currentSelection = groups.first(where: { $0.id == selectedGroupID }) {
            selectedGroupID = currentSelection.id
            return
        }

        if pack.id == group.parent?.id,
           let currentGroup = groups.first(where: { $0.id == group.id }) {
            selectedGroupID = currentGroup.id
            return
        }

        if let firstGroup = groups.first {
            selectedGroupID = firstGroup.id
        } else {
            selectedGroupID = ""
        }
    }

    private func handleMoveConfirmation() {
        guard let destinationGroup = selectedDestinationGroup else { return }

        performMoveOrCopy(to: destinationGroup, copy: keepSourceItem)
        lastMovePackID = selectedPackID
        lastMoveGroupID = destinationGroup.id
        lastMoveInsertPositionRawValue = moveInsertPosition.rawValue
        lastMoveKeepOriginal = keepSourceItem
        isShowingMoveSheet = false
        onDismiss()
    }
    /// 移動 or 複写を実行する
    private func performMoveOrCopy(to destinationGroup: M2Group, copy: Bool) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        // 移動時も order のみを真実とするため、sourceGroup.child には触れない

        let destinationItems = destinationGroup.child.sorted { $0.order < $1.order }
        let insertIndex: Int
        switch moveInsertPosition {
        case .start:
            insertIndex = 0
        case .end:
            insertIndex = destinationItems.count
        }
        let clampedIndex = max(0, min(insertIndex, destinationItems.count))

        let newOrder = sparseOrderForInsertion(items: destinationItems, index: clampedIndex) {
            // child を再代入せずに order のみ補正する
            normalizeSparseOrders(destinationItems)
        }

        if copy {
            let newItem = M3Item(name: item.name,
                                 memo: item.memo,
                                 stock: item.stock,
                                 need: item.need,
                                 weight: item.weight,
                                 order: newOrder,
                                 parent: destinationGroup)
            modelContext.insert(newItem)
        } else {
            item.parent = destinationGroup
            item.order = newOrder
        }
    }

    /// 編集対象のアイテムを選択する（前へ、次へ）
    /// - Parameter offset: 移動量 (-1)1つ前へ　(+1)1つ次へ
    private func selectAdjacentItem(by offset: Int) {
        guard let target = adjacentItem(offset: offset) else { return }
        withAnimation {
            onSelectItem(target)
        }
    }
    /// 前後のアイテムを取得する
    /// - Parameter offset: 移動量 (-1)1つ前のアイテム　(+1)1つ次のアイテム
    private func adjacentItem(offset: Int) -> M3Item? {
        if let provider = adjacentItemProvider {
            return provider(item, offset)
        }

        guard offset != 0,
              let parent = item.parent else { return nil }

        let orderedItems = parent.child.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }

        guard let currentIndex = orderedItems.firstIndex(where: { $0.id == item.id }) else {
            return nil
        }

        let destinationIndex = currentIndex + offset
        guard orderedItems.indices.contains(destinationIndex) else {
            return nil
        }

        return orderedItems[destinationIndex]
    }
    
    /// キーボードを隠す
    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var quantityCheckButton: some View {
        Button {
            item.check.toggle()
            if item.check {
                if linkCheckWithStock {
                    item.stock = item.need
                }
            } else {
                if linkCheckOffWithZero {
                    item.stock = 0
                }
            }
        } label: {
            Image(systemName:
                    item.check ? "checkmark.circle"
                    : item.need == 0 ? "circle.fill"
                    : item.need <= item.stock ? "circle.circle"
                    : "circle")
                .imageScale(.large)
                .tint(item.need == 0 ? .secondary : .accentColor)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating)
        }
        .buttonStyle(.borderless)
    }

    private var dialStyleBinding: Binding<DialStyle> {
        Binding(
            get: { DialStyle.builtin(id: dialStyleID) ?? .shape },
            set: { dialStyleID = $0.id }
        )
    }

    private var dialTuningBinding: Binding<AZDialInteractionTuning> {
        Binding(
            get: { PacklinDialSettings.loadTuning(from: dialTuningData) },
            set: { dialTuningData = PacklinDialSettings.encodeTuning($0) }
        )
    }

}

/// Popup用の簡易編集ビュー（数量のみ）
struct ItemQuickEditView: View {
    @Bindable var item: M3Item

    @Environment(\.modelContext) private var modelContext
    // 不揮発保存：チェックと在庫数を連動させる
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock

    /// === Fix 7: Undo グループ開閉のバランス保証フラグ ===
    /// ポップアップ表示でも onAppear / onDisappear が常に 1:1 とは限らないため、
    /// フラグで begin/end の対応を保証する。詳細は ItemEditView.swift の
    /// `isUndoGroupingActive` のコメント参照。
    @State private var isUndoGroupingActive: Bool = false

    init(item: M3Item) {
        self._item = Bindable(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // アイテム名称表示
            item.name.placeholderText("new.item")
                .font(FONT_NAME)
                .foregroundStyle(item.name.isEmpty ? COLOR_NAME_EMPTY : COLOR_NAME)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
            // 数量 編集
            ItemQuantityEditor(item: item)
        }
        .padding(8)
        .frame(width: 300)
        .onAppear {
            // === Fix 7: lifecycle 不均衡対策 ===
            // 二重 onAppear（ポップアップ再描画時など）でも 1 回だけ begin する
            beginUndoGroupingIfNeeded()
        }
        .onDisappear {
            // === Fix 7: lifecycle 不均衡対策 ===
            // チェックと在庫数を連動させる
            if linkCheckWithStock {
                item.check = (0 < item.need && item.need <= item.stock)
            }
            // begin したときだけ end する
            endUndoGroupingIfNeeded()
        }
    }

    /// === Fix 7: Undo グループの安全な開始 ===
    /// `isUndoGroupingActive` フラグで再入を防止する。
    private func beginUndoGroupingIfNeeded() {
        guard !isUndoGroupingActive else { return }
        modelContext.undoManager?.groupingBegin()
        isUndoGroupingActive = true
    }

    /// === Fix 7: Undo グループの安全な終了 ===
    /// `isUndoGroupingActive` が立っているときだけ end を呼ぶ。
    private func endUndoGroupingIfNeeded() {
        guard isUndoGroupingActive else { return }
        modelContext.undoManager?.groupingEnd()
        isUndoGroupingActive = false
    }
}

// 数量 編集
private struct ItemQuantityEditor: View {
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    @Bindable var item: M3Item
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(PacklinDialSettings.styleKey) private var dialStyleID = DialStyle.shape.id
    @AppStorage(PacklinDialSettings.tuningKey) private var dialTuningData = Data()

    init(item: M3Item) {
        self._item = Bindable(item)
    }

    private struct FieldConfig {
        let title: LocalizedStringKey
        let unit: LocalizedStringKey
        let maxValue: Int
        let step: Int       // AZDial のドラッグ1単位あたりの変化量
        let binding: Binding<Int>
    }

    private var fields: [FieldConfig] {
        [
            // 個重量
            FieldConfig(title: "weight.per.item", unit: "g",
                        maxValue: APP_MAX_WEIGHT_NUM, step: 1, binding: weightBinding),
            // 在庫数
            FieldConfig(title: "stock.count", unit: "pcs",
                        maxValue: APP_MAX_STOCK_NUM, step: 1, binding: stockBinding),
            // 必要数
            FieldConfig(title: "needed", unit: "pcs",
                        maxValue: APP_MAX_NEED_NUM, step: 1, binding: needBinding)
        ]
    }

    private var weightBinding: Binding<Int> {
        Binding(get: { item.weight }, set: { newValue in
            let value = max(0, newValue)
            if APP_MAX_WEIGHT_NUM < value {
                item.weight = APP_MAX_WEIGHT_NUM
            } else {
                item.weight = value
            }
        })
    }

    private var stockBinding: Binding<Int> {
        Binding(get: { item.stock }, set: { newValue in
            let value = max(0, newValue)
            if APP_MAX_STOCK_NUM < value {
                item.stock = APP_MAX_STOCK_NUM
            } else {
                item.stock = value
            }
            //連動しない item.check = (0 < item.stock && item.need <= item.stock)
        })
    }

    private var needBinding: Binding<Int> {
        Binding(get: { item.need }, set: { newValue in
            let value = max(0, newValue)
            if APP_MAX_NEED_NUM < value {
                item.need = APP_MAX_NEED_NUM
            } else {
                item.need = value
            }
            //連動しない item.check = (0 < item.stock && item.need <= item.stock)
        })
    }

    @State private var activeFieldIndex: Int? = nil

    private var usesCompactMetrics: Bool {
        horizontalSizeClass == .compact
    }

    // タイトル（個重量・在庫数・必要数）は「大」までで頭打ちなので、
    // FontScale が large 以上のときは「大」基準で十分な幅を確保すれば常に1行に収まる
    private var titleColumnWidth: CGFloat {
        switch fontScale {
        case .system, .standard:
            return usesCompactMetrics ? 44 : 56
        case .large, .xLarge:
            return usesCompactMetrics ? 64 : 72
        }
    }

    // 数値は「特大」のままユーザー設定で表示するため、xLarge ではさらに広めの枠を取る
    private var valueColumnWidth: CGFloat {
        switch fontScale {
        case .system, .standard:
            return usesCompactMetrics ? 58 : 75
        case .large:
            return usesCompactMetrics ? 76 : 90
        case .xLarge:
            return usesCompactMetrics ? 94 : 112
        }
    }

    private var valueHorizontalPadding: CGFloat {
        usesCompactMetrics ? 6 : 10
    }

    // 単位（g・個 / pcs など）も「大」までで頭打ち。
    // 英語の "pcs"（3文字）が1行で収まる幅を確保し、数値枠とも被らないようにする
    private var unitColumnWidth: CGFloat {
        switch fontScale {
        case .system, .standard:
            return usesCompactMetrics ? 18 : 30
        case .large, .xLarge:
            return usesCompactMetrics ? 30 : 38
        }
    }

    // 特大では数値が大きいぶん、単位とダイアルの間を広げて被りを避ける
    private var unitDialSpacing: CGFloat {
        fontScale == .xLarge ? 10 : 4
    }

    private var numberFont: Font {
        usesCompactMetrics ? .title3 : .title2
    }

    private var dialStyle: DialStyle {
        DialStyle.builtin(id: dialStyleID) ?? .shape
    }

    private var dialTuning: AZDialInteractionTuning {
        PacklinDialSettings.loadTuning(from: dialTuningData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                HStack(alignment: .center, spacing: 0) {
                    // 見出し（個重量・在庫数・必要数 / Weight per item など）
                    // 「大」までで頭打ちにする。短い名前（日本語など）は1行、
                    // 長い名前（英語の "Weight per item"）は2行で折り返して欠落を防ぐ
                    Text(field.title)
                        .font(usesCompactMetrics ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .multilineTextAlignment(.leading)
                        .frame(width: titleColumnWidth, alignment: .leading)
                        .cappedAtLargeFontSize()
                    // タップでテンキーシートを開く数値表示（数値はユーザー設定の文字サイズそのまま）
                    Button {
                        activeFieldIndex = index
                    } label: {
                        Text("\(field.binding.wrappedValue)")
                            .font(numberFont)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .multilineTextAlignment(.trailing)
                            .frame(width: valueColumnWidth)
                            .padding(.vertical, 6)
                            .padding(.horizontal, valueHorizontalPadding)
                            .background(COLOR_BACK_INPUT)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    // 単位（「大」までで頭打ち）
                    Text(field.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: unitColumnWidth)
                        .cappedAtLargeFontSize()
                    Spacer()
                        .frame(width: unitDialSpacing)
                    // ダイアル（Stepperの代わり）
                    // GeometryReader で残りスペースを計測し dialWidth に渡す
                    // 文字サイズが大きいときはタイトル/値/単位の枠が広がるため、
                    // ダイアルは残り幅に合わせて自動的に狭くなる（最小80pt）
                    GeometryReader { geo in
                        AZDialView(
                            value: field.binding,
                            min: 0,
                            max: field.maxValue,
                            step: field.step,
                            stepperStep: 0,
                            style: dialStyle,
                            dialWidth: max(80, min(220, geo.size.width)),
                            tuning: dialTuning
                        )
                    }
                    .frame(minWidth: 80, maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                }
            }
        }
        .padding(8)
        .sheet(isPresented: Binding(
            get: { activeFieldIndex != nil },
            set: { shown in if !shown { activeFieldIndex = nil } }
        )) {
            if let idx = activeFieldIndex {
                let field = fields[idx]
                NumericKeypadSheet(
                    title: field.title,
                    unit: field.unit,
                    placeholder: field.binding.wrappedValue,
                    maxValue: field.maxValue
                ) { newValue in
                    field.binding.wrappedValue = newValue
                }
                .appFontScale(fontScale)
            }
        }
    }
}

/// アイテム移動 設定シート
struct ItemMoveSheetView: View {
    let packs: [M1Pack]
    let itemName: String
    let fontScale: FontScale
    @Binding var selectedPackID: String
    @Binding var selectedGroupID: String
    @Binding var keepOriginal: Bool
    @Binding var insertPosition: ItemEditView.MoveInsertPosition
    let disableConfirm: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var sortedPacks: [M1Pack] {
        packs.sorted { $0.order < $1.order }
    }

    private var selectedPack: M1Pack? {
        sortedPacks.first(where: { $0.id == selectedPackID })
    }

    private var availableGroups: [M2Group] {
        guard let pack = selectedPack else { return [] }
        return pack.child.sorted { $0.order < $1.order }
    }

    private var titleText: Text {
        itemName.isEmpty ? Text("new.item") : Text(verbatim: itemName)
    }

    private var titleFont: Font {
        switch fontScale {
        case .large:
            return .title3.weight(.semibold)
        case .xLarge:
            return .title2.weight(.semibold)
        default:
            return .headline.weight(.semibold)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 移動先
                Section("to") {
                    // 移動先のPack
                    Picker(selection: $selectedPackID) {
                        ForEach(sortedPacks, id: \.id) { pack in
                            pack.name.truncTail(20)
                                .placeholderText("new.pack")
                                .tag(pack.id)
                        }
                    } label: {
                        Label("", systemImage: "case")
                            .foregroundStyle(.secondary) // ← ここで色を変更
                    }
                    .pickerStyle(.menu)  // メニュー型

                    
                    // 移動先のGroup
                    Picker(selection: $selectedGroupID) {
                        ForEach(availableGroups, id: \.id) { group in
                            group.name.truncTail(20)
                                .placeholderText("new.group")
                                .tag(group.id)
                        }
                    } label: {
                        Label("", systemImage: "square")
                            .foregroundStyle(.secondary) // ← ここで色を変更
                    }
                    .pickerStyle(.menu)  // メニュー型
                    .disabled(availableGroups.isEmpty)

                    // 移動先は先頭か末尾か
                    Picker("insert.position", selection: $insertPosition) {
                        ForEach(ItemEditView.MoveInsertPosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 移動元
                Section("from") {
                    // コピーを作成する
                    Toggle("make.copy", isOn: $keepOriginal)
                }
            }
            // スクロール位置表示は全画面で出さない
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            //.listSectionSpacing(.compact)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // 閉じる
                        //dismiss()
                        onCancel()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 移動 or 複写
                    Button(LocalizedStringKey(keepOriginal ? "copy.2" : "move.2"), action: onConfirm)
                        .disabled(disableConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .padding(.horizontal, 16)
                }
                ToolbarItem(placement: .principal) {
                    titleText
                        .font(titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct EditorSection<Content: View>: View {
    private let title: LocalizedStringKey?
    private let content: Content

    init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}
