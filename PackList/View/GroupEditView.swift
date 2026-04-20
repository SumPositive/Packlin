//
//  GroupEditView.swift
//  PackList
//
//  Created by sumpo on 2025/09/14.
//

import SwiftUI
import SwiftData

struct GroupEditView: View {
    @Bindable var group: M2Group

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // 不揮発保存：チェックと在庫数を連動させる
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock
    @AppStorage(AppStorageKey.linkCheckOffWithZero) private var linkCheckOffWithZero: Bool = DEF_linkCheckOffWithZero
    // 不揮発保存：移動シート用の最終選択状態
    @AppStorage("groupEdit.move.lastPackID") private var lastMovePackID: String = ""
    @AppStorage("groupEdit.move.lastInsertPosition") private var lastMoveInsertPositionRawValue: String = MoveInsertPosition.end.rawValue
    @AppStorage("groupEdit.move.lastKeepOriginal") private var lastMoveKeepOriginal: Bool = false

    @FocusState private var nameIsFocused: Bool
    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]

    @State private var isShowingMoveSheet = false
    @State private var selectedPackID: String
    @State private var keepSourceGroup = false
    @State private var moveInsertPosition: MoveInsertPosition = .end

    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check || $0.need == 0 }
    }

    private var sortedPacks: [M1Pack] {
        // orderを唯一の真実とするため、毎回並べ替えてから扱う
        packs.sorted { $0.order < $1.order }
    }

    private var selectedPack: M1Pack? {
        // 現在の選択IDに一致するPackを取得
        sortedPacks.first(where: { $0.id == selectedPackID })
    }

    enum MoveInsertPosition: String, CaseIterable, Identifiable {
        case start
        case end

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .start:
                return "パックの先頭"
            case .end:
                return "パックの末尾"
            }
        }
    }

    init(group: M2Group) {
        self._group = Bindable(group)
        // グループが属しているPackを初期選択として保持する
        self._selectedPackID = State(initialValue: group.parent?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    actionBar

                    editCard(title: "グループ名", minHeight: 74) {
                        TextEditor(text: $group.name)
                            .font(FONT_EDIT)
                            .scrollContentBackground(.hidden)
                            .onChange(of: group.name) { oldValue, newValue in
                                // 最大文字数制限
                                if APP_MAX_NAME_LEN < newValue.count {
                                    group.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                                }
                            }
                            .focused($nameIsFocused) // フォーカス状態とバインド
                    }

                    editCard(title: "メモ", minHeight: 112) {
                        TextEditor(text: $group.memo)
                            .font(FONT_EDIT)
                            .scrollContentBackground(.hidden)
                            .onChange(of: group.memo) { oldValue, newValue in
                                // 最大文字数制限
                                if APP_MAX_MEMO_LEN < newValue.count {
                                    group.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("グループ編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // 閉じる
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .onAppear {
            // Undo grouping BEGIN
            modelContext.undoManager?.groupingBegin()
            if group.name.isEmpty {
                nameIsFocused = true
            }
        }
        .onDisappear() {
            // 末尾のスペースと改行を除去
            group.name = group.name.trimTrailSpacesAndNewlines
            group.memo = group.memo.trimTrailSpacesAndNewlines
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            GroupMoveSheetView(packs: sortedPacks,
                               groupName: group.name,
                               selectedPackID: $selectedPackID,
                               keepOriginal: $keepSourceGroup,
                               insertPosition: $moveInsertPosition,
                               disableConfirm: selectedPack == nil,
                               onConfirm: handleMoveConfirmation,
                               onCancel: { isShowingMoveSheet = false })
                .presentationDetents([.height(330)])
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            compactActionButton(title: allItemsChecked ? "チェックOFF" : "チェックON",
                                fixedWidth: 82,
                                systemImage: allItemsChecked ? "checkmark.square" : "square",
                                tint: .accentColor,
                                action: checkToggle)

            compactActionButton(title: "複製",
                                systemImage: "plus.square.on.square",
                                tint: .accentColor) {
                group.duplicate()
            }

            compactActionButton(title: "移動",
                                systemImage: "hand.point.up.left.and.text",
                                tint: .blue) {
                prepareMoveSheet()
                isShowingMoveSheet = true
            }

            Spacer(minLength: 0)

            compactActionButton(title: "削除",
                                systemImage: "trash",
                                tint: .red) {
                // シートを閉じてから削除処理を行う
                dismiss()
                group.delete()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .buttonStyle(.borderless)
    }

    private func compactActionButton(title: LocalizedStringKey,
                                     fixedWidth: CGFloat? = nil,
                                     systemImage: String,
                                     tint: Color,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(minWidth: 64)
            .frame(width: fixedWidth)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .tint(tint)
    }

    private func editCard<Content: View>(title: LocalizedStringKey,
                                         minHeight: CGFloat,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
                .frame(minHeight: minHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    /// 従来どおり、配下の全item.checkを現在の全チェック状態から反転する。.stockは設定に応じて連動する
    private func checkToggle() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        let checked = !allItemsChecked
        let items = group.child
        for item in items {
            if checked {
                // OFF --> ON
                item.check = (0 < item.need)
                // チェックと在庫数を連動させる
                if linkCheckWithStock {
                    item.stock = item.need
                }
            } else {
                // ON --> OFF
                item.check = false
                if linkCheckOffWithZero {
                    // チェックOFF時の在庫クリアは新設フラグで制御
                    item.stock = 0
                }
            }
        }
    }

    /// 移動シートを表示する前に前回の選択内容を同期する
    private func prepareMoveSheet() {
        keepSourceGroup = lastMoveKeepOriginal
        if let storedInsertPosition = MoveInsertPosition(rawValue: lastMoveInsertPositionRawValue) {
            moveInsertPosition = storedInsertPosition
        } else {
            moveInsertPosition = .end
        }

        // 前回選択したPackが存在すれば再利用する。無ければ現在所属Packを使う
        if let storedPack = sortedPacks.first(where: { $0.id == lastMovePackID }) {
            selectedPackID = storedPack.id
        } else if let currentPackID = group.parent?.id,
                  sortedPacks.contains(where: { $0.id == currentPackID }) {
            selectedPackID = currentPackID
        } else if let firstPack = sortedPacks.first {
            selectedPackID = firstPack.id
        } else {
            selectedPackID = ""
        }
    }

    /// 移動確定時の処理
    private func handleMoveConfirmation() {
        guard let destinationPack = selectedPack else { return }

        performMoveOrCopy(to: destinationPack, copy: keepSourceGroup)
        lastMovePackID = destinationPack.id
        lastMoveInsertPositionRawValue = moveInsertPosition.rawValue
        lastMoveKeepOriginal = keepSourceGroup
        isShowingMoveSheet = false
        dismiss()
    }

    /// Groupを移動または複製する
    private func performMoveOrCopy(to destinationPack: M1Pack, copy: Bool) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        let destinationGroups = destinationPack.child.sorted { $0.order < $1.order }
        let insertIndex: Int
        switch moveInsertPosition {
        case .start:
            insertIndex = 0
        case .end:
            insertIndex = destinationGroups.count
        }
        let clampedIndex = max(0, min(insertIndex, destinationGroups.count))

        let newOrder = sparseOrderForInsertion(items: destinationGroups, index: clampedIndex) {
            // child配列は触らずorderのみ補正
            normalizeSparseOrders(destinationGroups)
        }

        if copy {
            // グループ本体を複製して新しいPackへ追加する
            let newGroup = M2Group(name: group.name,
                                   memo: group.memo,
                                   order: newOrder,
                                   parent: destinationPack)
            modelContext.insert(newGroup)

            // アイテムも順番を保ったまま複製する
            let orderedItems = group.child.sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.id < rhs.id
            }
            for item in orderedItems {
                let newItem = M3Item(name: item.name,
                                     memo: item.memo,
                                     stock: item.stock,
                                     need: item.need,
                                     weight: item.weight,
                                     order: item.order,
                                     parent: newGroup)
                modelContext.insert(newItem)
            }
        } else {
            // グループを別Packへ移動し、orderを更新する
            group.parent = destinationPack
            group.order = newOrder
        }
    }
}

/// グループ移動用のシート
private struct GroupMoveSheetView: View {
    let packs: [M1Pack]
    let groupName: String
    @Binding var selectedPackID: String
    @Binding var keepOriginal: Bool
    @Binding var insertPosition: GroupEditView.MoveInsertPosition
    let disableConfirm: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var sortedPacks: [M1Pack] {
        // パック一覧もorder順で扱う
        packs.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("移動先") {
                    // 送り先のパック選択
                    Picker(selection: $selectedPackID) {
                        ForEach(sortedPacks, id: \.id) { pack in
                            pack.name.truncTail(20)
                                .placeholderText("新しいパック")
                                .tag(pack.id)
                        }
                    } label: {
                        Label("", systemImage: "case")
                            .foregroundStyle(.secondary)
                    }
                    .pickerStyle(.menu)

                    // 挿入位置（先頭 or 末尾）
                    Picker("挿入位置", selection: $insertPosition) {
                        ForEach(GroupEditView.MoveInsertPosition.allCases) { position in
                            Text(position.titleKey)
                                .tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("移動元") {
                    // 元のグループを残す（複製）かどうか
                    Toggle("コピーを作成する（複製）", isOn: $keepOriginal)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(keepOriginal ? "複製する" : "移動する", action: onConfirm)
                        .disabled(disableConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .padding(.horizontal, 16)
                }
            }
            .navigationTitle(groupName.placeholder("新しいグループ"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
