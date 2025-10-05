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
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @FocusState private var nameIsFocused: Bool

    @State private var isShowingCheckAlert = false
    @State private var pendingCheckAlert: CheckAlertType = .checkOn

    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        VStack {
            HStack {    // Actions
                // チェックON/OFF
                Button {
                    prepareCheckAlert()
                } label: {
                    VStack {
                        if allItemsChecked {
                            Image(systemName: "checkmark.square")
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            Text("action.check.off")
                                .font(.caption)
                        }else{
                            Image(systemName: "square")
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            Text("action.check.on")
                                .font(.caption)
                        }
                    }
                }
                .tint(.purple)
                .padding(.horizontal, 8)
                
                // 複製
                Button {
                    duplicateGroup()
                } label: {
                    VStack {
                        Image(systemName: "plus.square.on.square")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("action.duplicate")
                            .font(.caption)
                    }
                }
                .tint(.accentColor)
                .padding(.horizontal, 8)
                
                Spacer()

                // 削除
                Button {
                    // EditItemViewを閉じる
                    onClose()
                    // Itemを削除する
                    deleteGroup()
                } label: {
                    VStack {
                        Image(systemName: "trash")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("action.delete")
                            .font(.caption)
                    }
                }
                .tint(.red)
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 8)

            HStack {
                Text("edit.name")
                    .font(.caption)
                Spacer()
            }
            .padding(.bottom, -7)
            TextEditor(text: $group.name)
                .font(FONT_EDIT)
                .onChange(of: group.name) { oldValue, newValue in
                    // 最大文字数制限
                    if APP_MAX_NAME_LEN < newValue.count {
                        group.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                    }
                }
                .focused($nameIsFocused) // フォーカス状態とバインド
                .frame(height: 80)

            HStack {
                Text("edit.memo")
                    .font(.caption)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, -7)
            TextEditor(text: $group.memo)
                .font(FONT_EDIT)
                .onChange(of: group.memo) { oldValue, newValue in
                    // 最大文字数制限
                    if APP_MAX_MEMO_LEN < newValue.count {
                        group.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                    }
                }
                .frame(height: 80)
        }
        .padding(.horizontal, 8)
        .frame(width: 320, height: 280)
        .alert(alertTitle, isPresented: $isShowingCheckAlert, actions: {
            switch pendingCheckAlert {
            case .checkOn:
                Button("alert.check.on.only") {
                    applyCheckToggle(shouldCheck: true, adjustStock: false)
                }
                Button("alert.check.on.sufficient") {
                    applyCheckToggle(shouldCheck: true, adjustStock: true)
                }
            case .checkOff:
                Button("alert.check.off.only") {
                    applyCheckToggle(shouldCheck: false, adjustStock: false)
                }
                Button("alert.check.off.insufficient") {
                    applyCheckToggle(shouldCheck: false, adjustStock: true)
                }
            }
            Button("action.cancel", role: .cancel) {}
        }, message: {
            Text(alertMessage)
        })
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
    }

    /// チェック・トグル；配下の全item.checkを反転する。.stockはそのまま
    ///   - shouldCheck:  True=チェックONにする／OFFにする
    ///   - adjustStock:  True=在庫数も変更する／しない
    private func applyCheckToggle(shouldCheck: Bool, adjustStock: Bool) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        let items = group.child
        for item in items {
            if shouldCheck {
                // OFF --> ON
                item.check = (0 < item.need)
                // チェックON時に充足（在庫数＝必要数）にする
                if adjustStock {
                    item.stock = item.need
                }
            } else {
                // ON --> OFF
                item.check = false
                // チェックOFF時に不足（在庫数＝0）にする
                if adjustStock {
                    item.stock = 0
                }
            }
        }
    }

    /// 全チェック・アラート表示
    private func prepareCheckAlert() {
        guard !group.child.isEmpty else { return }

        pendingCheckAlert = allItemsChecked ? .checkOff : .checkOn
        isShowingCheckAlert = true
    }
    /// 全チェック・アラート　タイトル
    private var alertTitle: String {
        switch pendingCheckAlert {
        case .checkOn:
            return String(localized: "alert.check.on.title")
        case .checkOff:
            return String(localized: "alert.check.off.title")
        }
    }
    /// 全チェック・アラート　メッセージ
    private var alertMessage: String {
        switch pendingCheckAlert {
        case .checkOn:
            return String(localized: "alert.check.on.message")
        case .checkOff:
            return String(localized: "alert.check.off.message")
        }
    }

    /// 現在のGroupを複製して現在行に追加する
    private func duplicateGroup() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        guard let parent = group.parent else { return }
        let newGroup = M2Group(name: group.name, memo: group.memo,
                               order: parent.nextGroupOrder(),
                               parent: parent)
        modelContext.insert(newGroup)
        withAnimation {
            if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
                // 現在行の下に追加
                parent.child.insert(newGroup, at: index + 1)
            }
            parent.normalizeGroupOrder()
        }
        for item in group.child {
            copyItem(item, to: newGroup)
        }
    }
    private func copyItem(_ item: M3Item, to parent: M2Group) {
        let newItem = M3Item(name: item.name, memo: item.memo,
                             stock: item.stock, need: item.need, weight: item.weight,
                             order: parent.nextItemOrder(), parent: parent)
        modelContext.insert(newItem)
        parent.child.append(newItem)
        parent.normalizeItemOrder()
    }

    /// 現在のGroupを削除する
    private func deleteGroup() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        // groupの配下を削除
        for item in group.child {
            modelContext.delete(item)
        }
        // groupを削除：pack側から削除して整列する
        if let parent = group.parent,
           let index = parent.child.firstIndex(where: { $0.id == group.id }) {
            parent.child.remove(at: index)
            parent.normalizeGroupOrder()
        }
        modelContext.delete(group)
    }

}

/// 全チェック・アラート　タイプ
private enum CheckAlertType {
    case checkOn  // ONにする
    case checkOff // OFFにする
}

