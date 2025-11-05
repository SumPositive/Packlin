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

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    @AppStorage(AppStorageKey.footerMessage) private var footerMessage: Bool = true

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingGroup: M2Group?
    @State private var popupAnchor: CGPoint?
    @State private var showAiCreateSheet = false // AI修正シートの表示状態を保持（ボタンタップで開く）

    private let rowHeight: CGFloat = 44

    private var sortedGroups: [M2Group] {
        pack.child.sorted { $0.order < $1.order }
    }
    
    // Popup表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingPopup: Bool { editingGroup != nil }

    
    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(sortedGroups) { group in
                        ZStack {
                            GroupRowView(group: group, isHeader: false) { selected, point in
                                editingGroup = selected
                                popupAnchor = point
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
                    }
                    .onMove(perform: moveGroup)
                }
                // 並べ替え一覧
                Section {
                    ForEach(ItemSortOption.allCases) { option in
                        NavigationLink(value: AppDestination.itemSortList(packID: pack.id, sort: option)) {
                            HStack {
                                Text(option.title)
                                    .font(FONT_MEMO)
                                    .foregroundStyle(COLOR_MEMO)
                                Spacer()
                            }
                            .frame(minHeight: rowHeight)
                            .overlay(alignment: .bottom) {
                                // 独自の下線
                                COLOR_LIST_SEPARATOR
                                    .frame(height: LIST_SEPARATOR_THICKNESS)
                                    .ignoresSafeArea(edges: .horizontal)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .padding(.horizontal, 32)
                    }
                    .padding(.horizontal, 16)
                }
                header: {
                    VStack {
                        Button {
                            // AI修正シートを開いて、現在のパック内容を基にチャッピーへ依頼する
                            showAiCreateSheet = true
                            GALogger.log(.function(name: "group_list", option: "tap_ai_create"))
                        } label: {
                            Label {
                                // 太字テキストで「チャッピー(AI)に作ってもらおう」を表示し、操作の目的を明確化
                                Text("チャッピー(AI)に依頼する")
                                    .font(.body.weight(.medium))
                                    .multilineTextAlignment(.center)
                            } icon: {
                                // きらめきアイコンでAIアシストであることを視覚的に伝える
                                Image(systemName: "sparkles")
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .padding(.bottom, 12)
                        // セクション2・ヘッダー タイトル
                        HStack {
                            Text("並べ替え一覧 & アイテム検索")
                                .font(.body.weight(.bold))
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 30)
                }
                footer: {
                    if footerMessage {
                        // セクション2・フッター：操作説明、アイコン説明
                        Section2FooterView()
                            .listRowSeparator(.hidden) // 下線なし
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
            .padding(.horizontal, 0)
            .navigationTitle(pack.name.placeholderText("placeholder.pack.new"))
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(isShowingPopup)
                    .padding(.trailing, 8)

                    Button {
                        canUndo = false
                        modelContext.undoManager?.performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(!canUndo || isShowingPopup)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        canRedo = false
                        modelContext.undoManager?.performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(!canRedo || isShowingPopup)
                    .padding(.trailing, 8)

                    Button(action: addGroup) {
                        Image(systemName: "plus.square")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(isShowingPopup)
                }
            }
            .onAppear {
                updateUndoRedo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedo, object: nil)) { _ in
                updateUndoRedo()
            }

            //----------------------------------
            //(ZStack 1) Popupで表示
            if let group = editingGroup {
                PopupView(anchor: popupAnchor) {
                    editingGroup = nil
                    popupAnchor = nil
                } content: {
                    GroupEditView(group: group) {
                        //.onClose：内から閉じる場合
                        editingGroup = nil
                        popupAnchor = nil
                    }
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
                        editingGroup = nil
                        popupAnchor = nil
                        return
                    }

                    guard horizontal > 80, abs(vertical) < 50 else { return }
                    dismiss()
                }
        )
        .sheet(isPresented: $showAiCreateSheet) {
            // 現在のパック情報をそのままAIへ渡し、修正提案を依頼できるようにする
            AiCreateSheetView(basePack: pack)
                // シートの高さが常に最大にならないように、中程度の高さを優先して表示する
                // iOS標準のmedium detentは内容量が少ないときに最小限の高さで止まり、必要に応じてlargeまで広がる
                .presentationDetents([.medium, .large])
                // ユーザーが高さを変更できることを明示するため、ドラッグインジケータを表示する
                .presentationDragIndicator(.visible)
        }
    }
    
    /// セクション2・フッター：操作説明、アイコン説明
    struct Section2FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("groupList.footer.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.square")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("groupList.footer.checked")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.square")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("groupList.footer.inStock")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "square")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("groupList.footer.outOfStock")
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


    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo && modelContext.hasChanges // && 編集なければ非活性
            canRedo = um.canRedo
        } else {
            canUndo = false
            canRedo = false
        }
    }

    private func addGroup() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
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

    private func moveGroup(from source: IndexSet, to destination: Int) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

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
                assignSparseOrders(items: groups, range: index...end) {
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


#Preview {
    GroupListView(pack: M1Pack(name: "", order: 0))
}
