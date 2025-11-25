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
    @EnvironmentObject private var history: UndoStackService
    @EnvironmentObject private var navigationStore: NavigationStore

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    // 表示モード（初心者／上級者）をPackListと同じキーで共有し、ヘッダー表示を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default

    @State private var editingGroup: M2Group?
    @State private var popupAnchor: CGPoint?
    @State private var showAiCreateSheet = false // AI修正シートの表示状態を保持（ボタンタップで開く）

    // ヘッダーはボタン行＋タイトル行の2段構成にしつつ、上下余白を抑えて高さもコンパクトにする
    private var headerHeight: CGFloat { isBeginnerMode ? 96 : 64 }
    // 説明文を出すかどうかのフラグを共通にまとめる
    private var isBeginnerMode: Bool { displayMode == .beginner }

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }
    
    // Group編集はシート表示へ移行したため、Popupは利用しない
    // それでも編集中はツールバー操作を抑制したいので、フラグ名は流用
    private var isShowingPopup: Bool { editingGroup != nil }

    // Group一覧の下に固定表示するメニュー（縦幅を抑えてアイコン＋短文を横並びに）
    private var footerMenu: some View {
        VStack(spacing: 0) {
            COLOR_LIST_SEPARATOR
                .frame(height: LIST_SEPARATOR_THICKNESS)
                .ignoresSafeArea(edges: .horizontal)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    NavigationLink(value: AppDestination.itemSortList(packID: pack.id, sort: .unchecked)) {
                        // アイコン右に短いテキストを並べ、カプセル風の縁取りで押しやすさを残す
                        HStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)

                            Text(LocalizedStringKey("アイテム縦覧"))
                                // フォントを小さく軽めにして縦幅を抑える
                                .font(.footnote.weight(.regular))
                                .foregroundStyle(Color.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                        // 薄い塗りと境界線でカプセル風に仕上げる
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if isBeginnerMode {
                        // 以前の長文ラベルはここで補足として表示し、ボタン内は短い語句で理解しやすくする
                        Text(LocalizedStringKey("全てのアイテムを対象に一覧・並べ替え・検索ができます"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    Button {
                        // 現在のパック内容をチャッピーに知らせ、AI提案を受ける
                        showAiCreateSheet = true
                        GALogger.log(.function(name: "group_list", option: "tap_ai_create"))
                    } label: {
                        // チャッピー相談ボタンもカプセル風にし、短い文言で高さを抑える
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)

                            Text(LocalizedStringKey("チャッピー"))
                                // 同様に小さめ・軽めのフォントで縦幅を抑える
                                .font(.footnote.weight(.regular))
                                .foregroundStyle(Color.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 2)
                        // 右側ボタンも同じカプセル風の塗りと線を適用して統一感を出す
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if isBeginnerMode {
                        // AI依頼の流れはボタン外で丁寧に伝える（ボタンは短い文言で素早く押せるようにする）
                        Text(LocalizedStringKey("チャッピー(AI)に修正や変更を依頼できます"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            // フッターメニュー全体の上下余白を詰めて、画面占有を抑える
            .padding(.vertical, isBeginnerMode ? 8 : 6)
            .background(.ultraThinMaterial)
        }
    }

    
    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(sortedGroups) { group in
                        ZStack {
                            GroupRowView(group: group, isHeader: false) { selected, _ in
                                editingGroup = selected
                                // シート表示では座標が不要なためリセット
                                popupAnchor = nil
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
                        // 行のトップレベルでスワイプ操作を受け付けるようにする
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { // 左スワイプ・アクション（全スワイプ即削除を避ける）
                            // グループ削除（行コンテナで定義してスワイプ無効化を防ぐ＋フルスワイプ事故を防止）
                            Button {
                                group.delete()
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                            .tint(.orange)
                            .disabled(group.parent == nil)
                            
                            // グループ複製
                            Button {
                                group.duplicate()
                            } label: {
                                Label("複製", systemImage: "plus.square.on.square")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove(perform: moveGroup)
                }
                // 並べ替え一覧
                footer: {
                    if isBeginnerMode {
                        // 初心者モードでは操作説明をフッターに表示して迷いを減らす
                        Section2FooterView()
                            .listRowSeparator(.hidden) // 下線なし
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
            .padding(.horizontal, 0)
            //.navigationTitle(pack.name.placeholderText("新しいパック"))
            .navigationBarBackButtonHidden(true)
            //.toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) { // ヘッダ部
                // ボタン行の下に中央揃えのタイトル行を分けて、視線の向きを合わせやすくする
                // spacingも少し詰めて上下余白を半分程度に縮める
                VStack(alignment: .center, spacing: 6) {
                    HStack {
                        // 戻るボタンと初心者向け説明
                        VStack(spacing: 6) {
                            Button {
                                // アイテム一覧を閉じて親画面に戻る
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.backward")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isShowingPopup)

                            if isBeginnerMode {
                                Text("パック一覧に戻る")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 76)
                        .padding(.horizontal, 6)

                        // Undoボタンと説明
                        VStack(spacing: 6) {
                            Button {
                                // 履歴サービスを介して一括で巻き戻す
                                history.undo(context: modelContext)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .disabled(!history.canUndo || isShowingPopup)

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

                        // Redoボタンと説明
                        VStack(spacing: 6) {
                            Button {
                                // Undoで戻した内容を再適用する
                                history.redo(context: modelContext)
                            } label: {
                                Image(systemName: "arrow.uturn.forward")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .disabled(!history.canRedo || isShowingPopup)

                            if isBeginnerMode {
                                Text("直前の変更にやり直す")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 76)
                        .padding(.horizontal, 6)

                        // 新しいグループ追加と説明
                        VStack(spacing: 6) {
                            Button(action: addGroup) {
                                Image(systemName: "plus.square")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isShowingPopup)

                            if isBeginnerMode {
                                Text("新しいグループを追加する")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 92)
                        .padding(.horizontal, 6)
                    }

                    // タイトルはボタン行の下に1行で配置し、省スペースでも欠けないようにする
                    // 中央に寄せることで、左右どちらのボタンを主に使う場合でも目線の移動を少なくする
                    Text(pack.name.placeholder("新しいパック"))
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .tint(.primary)
                .frame(height: headerHeight)
                .padding(.horizontal, 8)
                // ヘッダーの上下余白を控えめにしてコンテンツの見える領域を増やす
                .padding(.vertical, 3)
                .background(.thinMaterial)
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
                        editingGroup = nil
                        popupAnchor = nil
                        return
                    }

                    if horizontal <= 80 || abs(vertical) >= 50 { return }
                    dismiss()
                }
        )
        // Group編集用のシートを追加
        .sheet(item: $editingGroup, onDismiss: {
            popupAnchor = nil
        }) { group in
            GroupEditView(group: group)
                .presentationDetents([.height(580)])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAiCreateSheet) {
            // 現在のパック情報をそのままAIへ渡し、修正提案を依頼できるようにする
            AiCreateSheetView(basePack: pack)
                .presentationDetents([.height(AiCreateSheetView_HEIGHT), .large])
                .presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .bottom) {
            footerMenu
        }
    }
    
    /// セクション2・フッター：ボタンの説明
    struct Section2FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("ボタンの説明")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "square")
                            .imageScale(.medium)
                        Text("グループの名称やメモを編集する")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .imageScale(.medium)
                            .padding(.leading, 4)
                            .padding(.trailing, 2)
                        Text("アイテム一覧を表示する")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .imageScale(.medium)
                        Text("ドラッグドロップで行を移動する")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)

                Text("グループの状態")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "square")
                            .imageScale(.large)
                        Text("不足（必要数に満たない、在庫が足りない）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.square")
                            .imageScale(.large)
                        Text("充足（必要数を満たしている、十分な在庫あり）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.square")
                            .imageScale(.large)
                        Text("✔︎済（グループ内の必要なアイテムが全てチェック済み）")
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
        }
    }

    private func addGroup() {
        // 新しいグループ追加を1操作として履歴化する
        history.perform(context: modelContext) {
            let orderedGroups = sortedGroups
            let insertionIndex: Int = {
                switch insertionPosition {
                case .head:
                    return 0
                case .tail:
                    return orderedGroups.count
                }
            }()

            let newOrder = sparseOrderForInsertion(items: orderedGroups, index: insertionIndex) {
                // order だけを整理して child 配列には手を出さない
                normalizeSparseOrders(orderedGroups)
            }

            let newGroup = M2Group(name: "", order: newOrder, parent: pack)
            modelContext.insert(newGroup)
            // child 配列はそのまま。表示時に order ソートされる
        }
    }

    /// Drag-Drop-Move
    private func moveGroup(from source: IndexSet, to destination: Int) {
        // 並べ替え操作もまとめて記録する
        history.perform(context: modelContext) {
            var groups = sortedGroups
            let movedIDs = Set(source.map { sortedGroups[$0].id })
            groups.move(fromOffsets: source, toOffset: destination)

            var index = 0
            while index < groups.count {
                if movedIDs.contains(groups[index].id) {
                    var end = index
                    while end + 1 < groups.count, movedIDs.contains(groups[end + 1].id) {
                        end += 1
                    }
                    assignSparseOrders(nodes: groups, range: index...end) {
                        // order の再配分だけを行い、pack.child は触れない
                        normalizeSparseOrders(groups)
                    }
                    index = end + 1
                } else {
                    index += 1
                }
            }
            // order を更新したので、List では order に基づいて並び替えられる
        }
    }
}


#Preview {
    GroupListView(pack: M1Pack(name: "", order: 0))
}
