//  パック一覧画面
//  パック表示、末尾追加、設定、Undo/Redo、編集シートをまとめる
//

import SwiftUI
import SwiftData
import UIKit


struct PackListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var history: UndoStackService

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    // 表示モード（初心者／上級者）をAppStorageで永続化
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .default
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default

    @State private var editingPack: M1Pack?
    @State private var popupAnchor: CGPoint?
    @State private var isShowSetting: Bool = false
    @State private var isShowAiCreateSheet: Bool = false
    @State private var isShowingPackAddPopover = false
    @State private var scrollTargetPackID: M1Pack.ID?
    @State private var scrollTargetPackAnchor: UnitPoint = .bottom

    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var sortedPacks: [M1Pack]

    private let rowHeight: CGFloat = 44
    // 初心者モードかどうかでヘッダーの説明を出し分ける
    private var isBeginnerMode: Bool { displayMode == .beginner }
    // ヘッダーの高さを表示モードで変える
    private var headerHeight: CGFloat {
        // 初心者ヘルプを欠けさせないよう、文字サイズに応じてヘッダーを高くする
        isBeginnerMode ? appHeaderHeightForBeginner(fontScale) : appHeaderHeightForExpert(fontScale, hasBreadcrumb: false)
    }
    // 編集シート表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingEditSheet: Bool { editingPack != nil }
    // シート表示時は自動モードも現在の外観へ解決して渡し、切り替え反映の遅れを避ける
    private var settingSheetColorScheme: ColorScheme? {
        appearanceMode.colorScheme ?? colorScheme
    }

    var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                List {
                    Section {
                        ForEach(sortedPacks) { pack in
                            ZStack {
                                PackRowView(pack: pack) { selected, point in
                                    // Pack行のタップ位置はシートでは使用しないが、今後の拡張に備えて保持
                                    editingPack = selected
                                    popupAnchor = point
                                }

                                GeometryReader { geo in
                                    // アイテム行と同じ見え方にするため、遷移アクセサリを右端から少し内側に置く
                                    let navigationLinkWidth = max(0, geo.size.width * 2.0 / 3.0 - 4)
                                    HStack(spacing: 0) {
                                        Button {
                                            editingPack = pack
                                            popupAnchor = CGPoint(
                                                x: geo.frame(in: .global).minX + geo.size.width / 6.0,
                                                y: geo.frame(in: .global).minY
                                            )
                                        } label: {
                                            Color.clear
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: geo.size.width / 3.0)

                                        NavigationLink(value: AppDestination.groupList(packID: pack.id)) {
                                            Color.clear
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: navigationLinkWidth)
                                    }
                                }
                            }
                            .id(pack.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        }
                        .onMove(perform: movePack)

                        AppendAtEndRowView(systemImage: "case",
                                           fontScale: fontScale,
                                           usesPackAddIcon: true,
                                           showsText: isBeginnerMode) {
                            addPackAtEndAndEdit()
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        // 高さは AppendAtEndRowView 内側の padding(.vertical, 8) で自動調整される
                        .environment(\.defaultMinListRowHeight, 0)
                    }
                    footer: {
                        if isBeginnerMode {
                            // 表示モードが初心者なら補足説明をフッターに表示する
                            FooterView()
                                .listRowSeparator(.hidden) // 下線なし
                        }
                    }
                }
                .listStyle(.plain)
                // List の規定最小行高さを 0 にして、AppendAtEndRowView が
                // 自然サイズ（コンテンツ + 上下8pt）で収まるようにする。
                // パック行自体は PackRowView 内の minHeight で最低高さを確保している
                .environment(\.defaultMinListRowHeight, 0)
                // スクロール位置表示は全画面で出さない
                .scrollIndicators(.hidden)
                .listRowSeparator(.hidden)
                // 区切り線は、Rowの.overlayで表示している
                .padding(.horizontal, 0)
                .onChange(of: scrollTargetPackID) { _, _ in
                    scrollToNewPackIfReady(scrollProxy)
                }
                .onChange(of: sortedPacks.map(\.id)) { _, _ in
                    scrollToNewPackIfReady(scrollProxy)
                }
            }
            .safeAreaInset(edge: .top) { // ヘッダ部
                HStack {
                    // 設定ボタンと説明
                    VStack(spacing: 6) {
                        Button {
                            // Setting
                            GALogger.log(.feature_use(name: "settings", source: "pack_list_header", detail: "open"))
                            popupAnchor = nil // 中央
                            isShowSetting = true
                        } label: {
                            Image(systemName: "gearshape")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 3.0))) // 回転
                        }
                        .buttonStyle(.borderless)
                        .disabled(isShowingEditSheet)

                        if isBeginnerMode {
                            // 初心者向け：ボタンの役割をテキストで補足
                            Text("open.settings")
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

                    // Undoボタンと説明
                    VStack(spacing: 6) {
                        Button {
                            // 履歴サービスへ委譲して巻き戻す
                            GALogger.log(.operation(name: "undo", target: "history", source: "pack_list_header", detail: nil, count: nil))
                            history.undo(context: modelContext)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        }
                        .buttonStyle(.borderless)
                        .disabled(!history.canUndo || isShowingEditSheet)

                        if isBeginnerMode {
                            // 初心者向け：巻き戻し操作の説明
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

                    // タイトル表示は見出しとして常に同じ大きさで見せたいので、Dynamic Typeの拡大縮小に左右されない固定サイズを指定
                    Text("app.title")
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .frame(minWidth: 50)

                    Spacer()

                    // Redoボタンと説明
                    VStack(spacing: 6) {
                        Button {
                            // 履歴サービスを用いて直前の変更にやり直す
                            GALogger.log(.operation(name: "redo", target: "history", source: "pack_list_header", detail: nil, count: nil))
                            history.redo(context: modelContext)
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        }
                        .buttonStyle(.borderless)
                        .disabled(!history.canRedo || isShowingEditSheet)

                        if isBeginnerMode {
                            // 初心者向け：Redoの役割を説明
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

                    // 新しいパック追加と説明
                    VStack(spacing: 6) {
                        Button {
                            // 標準Menuは文字サイズ対応しにくいため、独自popoverで選択肢を表示する
                            isShowingPackAddPopover = true
                        } label: {
                            // パック追加はカバン＋プラスの合成アイコンにする
                            ZStack {
                                Image(systemName: "case")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                                Image(systemName: "plus")
                                    .font(.system(size: 17, weight: .regular))
                                    .symbolRenderingMode(.hierarchical)
                                    .padding(.top, 4)
                            }
                            .foregroundStyle(COLOR_ADD_ACTION)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isShowingEditSheet)
                        .popover(
                            isPresented: $isShowingPackAddPopover,
                            attachmentAnchor: .point(.bottom),
                            arrowEdge: .top
                        ) {
                            PackAddPopoverView(
                                fontScale: fontScale,
                                onChappy: {
                                    isShowingPackAddPopover = false
                                    // チャッピー(AI)に新しいパックを作ってもらうフローへ誘導
                                    GALogger.log(.feature_use(name: "ai_create", source: "pack_list_add_popover", detail: "pack"))
                                    isShowAiCreateSheet = true
                                },
                                onManual: {
                                    isShowingPackAddPopover = false
                                    // これまで通り自分で項目を入力して作成するパターン
                                    addPack()
                                }
                            )
                            .presentationCompactAdaptation(.popover)
                        }

                        if isBeginnerMode {
                            // 初心者向け：新規パック追加の説明
                            Text("add.new.pack")
                                .font(.caption2)
                                .lineLimit(3)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                                .foregroundStyle(COLOR_ADD_ACTION)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 66)
                    .padding(.horizontal, 4)
                }
                // iPadのマルチウィンドウで左上のシステムアイコンに隠れないよう、ヘッダー全体を右へずらす
                .padding(.leading, ipadWindowControlInset())
                .tint(.primary) // ヘッダ部は.accentColorにしない
                .frame(height: headerHeight)
                .padding(.horizontal, 16)
                .background(.thinMaterial)
                // 初心者ヘルプ・タイトル・パンくずを「大」までで頭打ち
                .cappedAtLargeFontSize()
            }
        }
        // Pack編集はポップアップからシート表示へ移行
        .sheet(item: $editingPack) { pack in
            PackEditView(pack: pack)
                .appFontScale(fontScale)
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.hidden)
        }
        // 設定画面もシート表示へ変更
        .sheet(isPresented: $isShowSetting) {
            SettingView()
                .appFontScale(fontScale)
                .preferredColorScheme(settingSheetColorScheme)
                .presentationDetents([.height(SettingView_HEIGHT), .large])
                .presentationDragIndicator(.visible)
        }
        // 初心者モード時のAI新規作成メニューから遷移するシート
        .sheet(isPresented: $isShowAiCreateSheet) {
            ChappySheetView()
                .appFontScale(fontScale)
                .presentationDetents([.height(ChappySheetView_HEIGHT), .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// フッター：ボタンの説明
    struct FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("pack.status")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "case")
                            .imageScale(.large)
                        Text("lacking")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                            Image(systemName: "circle")
                                .imageScale(.small)
                                .padding(.top, 4)
                        }
                        Text("enough")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                            Image(systemName: "checkmark")
                                .imageScale(.small)
                                .padding(.top, 4)
                        }
                        Text("pack.items.all.checked")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)

                Text("re.beginner.mode.choose.expert.settings")
                    .font(.caption2)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .padding(.top, 20)
            .padding(.leading, 30)
            .padding(.trailing, 8)
            // 初心者ヘルプ「パックの状態」を「大」までで頭打ち
            .cappedAtLargeFontSize()
        }
    }

    private func addPack() {
        // 新規追加の位置設定ごとの利用頻度を匿名で集計する
        GALogger.log(.operation(name: "add", target: "pack", source: "header", detail: insertionPosition.rawValue, count: nil))
        var newPackID: M1Pack.ID?
        let scrollAnchor: UnitPoint = insertionPosition == .head ? .top : .bottom

        // 履歴サービスを利用して新規作成を1アクションとして記録する
        history.perform(context: modelContext) {
            let orderedPacks = Array(sortedPacks)
            let insertionIndex: Int = {
                switch insertionPosition {
                case .head:
                    return 0
                case .tail:
                    return orderedPacks.count
                }
            }()

            let newOrder = sparseOrderForInsertion(items: orderedPacks, index: insertionIndex) {
                normalizeSparseOrders(orderedPacks)
            }

            let newPack = M1Pack(name: "", order: newOrder)
            modelContext.insert(newPack)

            // 追加後のスクロール対象として新規Pack IDだけ保持する
            newPackID = newPack.id
        }

        popupAnchor = nil
        scrollTargetPackAnchor = scrollAnchor
        // 新規Packが見える位置までスクロールする
        scrollTargetPackID = newPackID
    }

    /// 末尾追加セル用：常に末尾へ追加して編集シートを開く
    private func addPackAtEndAndEdit() {
        // 末尾追加専用セルの利用頻度を集計する
        GALogger.log(.operation(name: "add", target: "pack", source: "append_end_row", detail: "tail", count: nil))
        var newPack: M1Pack?

        history.perform(context: modelContext) {
            let orderedPacks = Array(sortedPacks)
            let newOrder = sparseOrderForInsertion(items: orderedPacks, index: orderedPacks.count) {
                normalizeSparseOrders(orderedPacks)
            }

            let pack = M1Pack(name: "", order: newOrder)
            modelContext.insert(pack)

            newPack = pack
        }

        popupAnchor = nil
        if let newPack {
            scrollTargetPackAnchor = .bottom
            scrollTargetPackID = newPack.id
            editingPack = newPack
        }
    }

    /// 新規PackがListに反映されてからスクロールする
    private func scrollToNewPackIfReady(_ scrollProxy: ScrollViewProxy) {
        guard let packID = scrollTargetPackID,
              sortedPacks.contains(where: { $0.id == packID }) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                scrollProxy.scrollTo(packID, anchor: scrollTargetPackAnchor)
            }
            scrollTargetPackID = nil
        }
    }

    /// Drag-Drop-Move
    private func movePack(from source: IndexSet, to destination: Int) {
        // 並べ替えも1アクションにまとめる
        history.perform(context: modelContext) {
            var packs = Array(sortedPacks)
            let movedIDs = Set(source.map { sortedPacks[$0].id })
            packs.move(fromOffsets: source, toOffset: destination)

            var index = 0
            while index < packs.count {
                if movedIDs.contains(packs[index].id) {
                    var end = index
                    while end + 1 < packs.count, movedIDs.contains(packs[end + 1].id) {
                        end += 1
                    }
                    assignSparseOrders(nodes: packs, range: index...end) {
                        normalizeSparseOrders(packs)
                    }
                    index = end + 1
                } else {
                    index += 1
                }
            }
        }
    }
}

private struct PackAddPopoverView: View {
    let fontScale: FontScale
    let onChappy: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            optionButton(
                title: "let.chappy.ai.make",
                systemImage: "sparkles",
                action: onChappy
            )

            Divider()

            optionButton(
                title: "make.yourself",
                systemImage: "hand.tap",
                action: onManual
            )
        }
        .padding(14)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        .appFontScale(fontScale)
    }

    private func optionButton(
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 28)

                Text(title)
                    .font(.body.weight(.semibold))
                    // 大きい文字でも吹き出し内で欠けずに読めるよう折り返す
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

/// 共有メニュー画面
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        // SwiftUIの.sheet上でUIActivityViewControllerを表示すると背景が透過してしまうため、ここで背景色を明示的に塗りつぶす
        // systemBackgroundを指定することでダークモード・ライトモード双方で自然な色になる
        controller.view.backgroundColor = UIColor.systemBackground
        // isModalInPresentationをfalseにしておき、ユーザーが上スワイプで閉じられる通常動作を維持する
        controller.isModalInPresentation = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


#Preview {
    PackListView()
    //    EditPackView(pack: M1Pack(name: "TEST"))
}
