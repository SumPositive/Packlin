//
//  PackEditView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit


struct PackEditView: View {
    @Bindable var pack: M1Pack
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @FocusState private var nameIsFocused: Bool

    @State private var shareURL: URL?
    @State private var isPresentingShare = false
    @State private var isShowingCheckAlert = false
    @State private var pendingCheckAlert: CheckAlertType = .checkOn
    
    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        VStack {
            HStack {    // Actions
                // チェックON/OFF
                Button {
                    prepareCheckAlert()
                } label: {
                    VStack {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            
                            if allItemsChecked {
                                Image(systemName: "checkmark")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                    .padding(.top, 4)
                            }
                        }
                        if allItemsChecked {
                            Text("action.check.off")
                                .font(.caption)
                        }else{
                            Text("action.check.on")
                                .font(.caption)
                        }
                    }
                }
                .tint(.purple)
                .padding(.horizontal, 8)

                // 複製
                Button {
                    duplicatePack()
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

                // 共有
                Button {
                    exportPack()
                } label: {
                    VStack {
                        ZStack {
                            Image(systemName: "case")
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            Image(systemName: "arrow.up")
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                .padding(.top, -16)
                        }
                        Text("action.json.upload")
                            .font(.caption)
                    }
                }
                .tint(.accentColor)
                .padding(.leading, 16)
                
                Spacer()

                // 削除
                Button {
                    // EditItemViewを閉じる
                    onClose()
                    // Itemを削除する
                    deletePack()
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
            TextEditor(text: $pack.name)
                .font(FONT_EDIT)
                .onChange(of: pack.name) { oldValue, newValue in
                    // 最大文字数制限
                    if APP_MAX_NAME_LEN < newValue.count {
                        pack.name = String(newValue.prefix(APP_MAX_NAME_LEN))
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
            TextEditor(text: $pack.memo)
                .font(FONT_EDIT)
                .onChange(of: pack.memo) { oldValue, newValue in
                    // 最大文字数制限
                    if APP_MAX_MEMO_LEN < newValue.count {
                        pack.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                    }
                }
                .frame(height: 80)

            Text("edit.info.swipeToDismiss")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .frame(width: 320, height: 300)
        .sheet(isPresented: $isPresentingShare, onDismiss: cleanupShareResource) {
            if let shareURL {
                ActivityView(activityItems: [shareURL])
            }
        }
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
            if pack.name.isEmpty {
                nameIsFocused = true
            }
        }
        .onDisappear() {
            // 末尾のスペースと改行を除去
            pack.name = pack.name.trimTrailSpacesAndNewlines
            pack.memo = pack.memo.trimTrailSpacesAndNewlines
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

        let items = pack.child.flatMap { $0.child }
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
        let items = pack.child.flatMap { $0.child }
        guard !items.isEmpty else { return }

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

    /// 現在のPackを複製して現在行に追加する
    private func duplicatePack() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        let descriptor = FetchDescriptor<M1Pack>()
        let packs = (try? modelContext.fetch(descriptor)) ?? []
        let newOrder = M1Pack.nextPackOrder(packs)
        let newTitle = M1Pack(name: pack.name, memo: pack.memo, createdAt: pack.createdAt.addingTimeInterval(-0.001), order: newOrder)
        modelContext.insert(newTitle)
        for group in pack.child {
            copyGroup(group, to: newTitle)
        }
    }
    private func copyGroup(_ group: M2Group, to parent: M1Pack) {
        let newGroup = M2Group(name: group.name, memo: group.memo,
                               order: parent.nextGroupOrder(), parent: parent)
        modelContext.insert(newGroup)
        withAnimation {
            if let index = parent.child.firstIndex(where: { $0.id == group.id }) {
                // 下に追加
                parent.child.insert(newGroup, at: index + 1)
            } else {
                parent.child.append(newGroup)
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
    
    /// 現在のPackを削除する
    private func deletePack() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }
        // groupとその配下を削除
        for group in pack.child {
            deleteGroup(group)
        }
        // Packを削除
        modelContext.delete(pack)
        let descriptor = FetchDescriptor<M1Pack>()
        if let packs = try? modelContext.fetch(descriptor) {
            M1Pack.normalizePackOrder(packs)
        }
    }
    /// groupとその配下を削除
    private func deleteGroup(_ group: M2Group) {
        for item in group.child {
            modelContext.delete(item)
        }
        if let parent = group.parent,
           let index = parent.child.firstIndex(where: { $0.id == group.id }) {
            parent.child.remove(at: index)
            parent.normalizeGroupOrder()
        }
        modelContext.delete(group)
    }

    /// PackをJSONファイルにして共有(Export)する
    private func exportPack() {
        do {
            cleanupShareResource()

            let dto = pack.exportRepresentation()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(dto)

            let fileName = sanitizedFileName(from: pack.name.isEmpty
                                             ? pack.id : pack.name )
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName)
                .appendingPathExtension("json")

            try data.write(to: fileURL, options: [.atomic])

            shareURL = fileURL
            isPresentingShare = true
        } catch {
            debugPrint("Failed to export pack: \(error)")
        }
    }
    /// 一時共有ファイルを削除する
    private func cleanupShareResource() {
        defer {
            shareURL = nil
            isPresentingShare = false
        }

        guard let shareURL else { return }
        try? FileManager.default.removeItem(at: shareURL)
    }
    /// ファイル名を使用可能文字に制限する
    ///    shortUUIDをURLセーフにしたが、さらに念の為
    private func sanitizedFileName(from name: String) -> String {
        let base = "Pack_" + name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "\\/:?%*|\"<>\n")
        let components = base.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
        return sanitized.isEmpty ? "Pack_unnamed" : sanitized
    }
}

/// 全チェック・アラート　タイプ
private enum CheckAlertType {
    case checkOn  // ONにする
    case checkOff // OFFにする
}

