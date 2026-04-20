//
//  ItemListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
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

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    // PackListと共通の表示モードを参照し、初心者向け説明を切り替える
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingGroup: M2Group?
    @State private var editingItem: M3Item?
    @State private var popupAnchor: CGPoint?

    /// DBからソートして取得する（group.child は.order昇順）
    private var sortedItems: [M3Item] {
        group.child.sorted { $0.order < $1.order }
    }

    private let rowHeight: CGFloat = 44
    // 説明文表示判定をまとめておく
    private var isBeginnerMode: Bool { displayMode == .beginner }
    // ヘッダーの高さを表示モードで変える
    private var headerHeight: CGFloat { isBeginnerMode ? APP_HEADER_HEIGHT_BEG : APP_HEADER_HEIGHT_EXP }

    // Group編集はシートへ移行したが、アイテムのクイック編集は引き続きPopupを利用
    // そのため、どちらかが表示されている間はナビバーボタンを非活性にする
    private var isShowingPopup: Bool { editingGroup != nil || editingItem != nil }

    var body: some View {
        ZStack {
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
                            ItemRowView(item: item) { selected, point in
                                editingItem = selected
                                popupAnchor = point
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(COLOR_ROW_BACK)
                    }
                    .onMove(perform: moveItem)
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
            .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
            .padding(.horizontal, 8)
            .navigationBarBackButtonHidden(true)
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
                                Text("グループ一覧に戻る")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 50)
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
                        .frame(maxWidth: 55)
                        .padding(.horizontal, 6)

                        Spacer()
                        
                        if isBeginnerMode {
                            Text("アイテム\n一覧")
                                .font(.system(size: 15))
                                .lineLimit(2)
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
                                Text("戻した変更をやり直す")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 55)
                        .padding(.horizontal, 6)

                        // 新しいアイテム追加と説明
                        VStack(spacing: 6) {
                            Button(action: addItem) {
                                Image(systemName: "plus.circle")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.borderless)
                            .disabled(isShowingPopup)

                            if isBeginnerMode {
                                Text("新しいアイテムを追加する")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 74)
                        .padding(.horizontal, 6)
                    }

                    // パック＞グループのパンくずを並べ、各名称は画面幅の1/4までで自動省略する
                    BreadcrumbView(
                        packName: pack.name.placeholder("新しいパック"),
                        groupName: group.name.placeholder("新しいグループ"),
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
                .padding(.horizontal, 8)
                // ヘッダーの上下余白を抑えてリスト領域を広げる
                .padding(.vertical, 3)
                .background(.thinMaterial)
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
                        editingGroup = nil
                        editingItem = nil
                        popupAnchor = nil
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
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.hidden)
        }
    }

    /// フッター：ボタンの説明
    struct FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("アイテムの状態（未✔︎順）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .imageScale(.large)
                        Text("不足（必要数に満たない、在庫が足りない）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.circle")
                            .imageScale(.large)
                        Text("充足（必要数を満たしている、十分な在庫あり）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .imageScale(.large)
                        Text("✔︎済（数量に関わらずチェック済みである）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .imageScale(.large)
                        Text("不要（必要なし）")
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
    
    
    /// アイテム追加
    func addItem() {
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
        }
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
