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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // 不揮発保存：チェックと在庫数を連動させる
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = DEF_linkCheckWithStock
    @AppStorage(AppStorageKey.linkCheckOffWithZero) private var linkCheckOffWithZero: Bool = DEF_linkCheckOffWithZero
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default

    @FocusState private var nameIsFocused: Bool
    @FocusState private var memoIsFocused: Bool

    @State private var shareURL: URL?
    @State private var isPresentingShare = false
    @State private var showAiCreateSheet = false
    @State private var isTogglingCheck = false
    
    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    actionBar

                    editCard(title: "pack.name", minHeight: 74) {
                        PacklinMemoEditor(
                            placeholder: "enter.name.new.pack",
                            text: $pack.name,
                            isFocused: nameFocusBinding,
                            minHeight: 58,
                            maxLength: APP_MAX_NAME_LEN
                        )
                    }

                    editCard(title: "memo", minHeight: 112) {
                        PacklinMemoEditor(
                            placeholder: nil,
                            text: $pack.memo,
                            isFocused: memoFocusBinding,
                            minHeight: 96,
                            maxLength: APP_MAX_MEMO_LEN
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("edit.pack"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                navigationToolbar
            }
        }
        .sheet(isPresented: $isPresentingShare, onDismiss: cleanupShareResource) {
            if let shareURL {
                // 共有　パック保存
                ActivityView(activityItems: [shareURL])
            }
        }
        .onAppear {
            // Undo grouping BEGIN
            modelContext.undoManager?.groupingBegin()
            if pack.name.isEmpty {
                Task { @MainActor in
                    await Task.yield()
                    nameIsFocused = true
                }
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

    private var nameFocusBinding: Binding<Bool> {
        Binding(
            get: { nameIsFocused },
            set: { nameIsFocused = $0 }
        )
    }

    private var memoFocusBinding: Binding<Bool> {
        Binding(
            get: { memoIsFocused },
            set: { memoIsFocused = $0 }
        )
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            compactActionButton(title: LocalizedStringKey(allItemsChecked ? "check.off" : "check"),
                                fixedWidth: 108,
                                twoLineTitle: checkTwoLineTitle,
                                tint: .accentColor,
                                action: startCheckToggle) {
                ZStack {
                    Image(systemName: "case")
                        .imageScale(.large)
                        .symbolRenderingMode(.hierarchical)
                    if allItemsChecked {
                        Image(systemName: "checkmark")
                            .imageScale(.small)
                            .padding(.top, 4)
                    }
                }
            }
            .overlay(alignment: .center) {
                if isTogglingCheck {
                    // 起動直後など処理が重い瞬間はスピナーを表示して進捗を見せる
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .disabled(isTogglingCheck) // 進行中はタップを無効化

            compactActionButton(title: "copy",
                                systemImage: "plus.square.on.square",
                                tint: .accentColor) {
                pack.duplicate()
            }

            compactActionButton(title: "share",
                                systemImage: "square.and.arrow.up",
                                tint: .accentColor,
                                action: exportPack)

            Spacer(minLength: 0)

            compactActionButton(title: "delete",
                                systemImage: "trash",
                                tint: .red) {
                // シートを強制的に閉じてから削除処理へ進める
                dismiss()
                // Packを削除する
                pack.delete()
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
                                     systemImage: String,
                                     tint: Color,
                                     action: @escaping () -> Void) -> some View {
        compactActionButton(title: title, tint: tint, action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func compactActionButton<Icon: View>(title: LocalizedStringKey,
                                                 fixedWidth: CGFloat? = nil,
                                                 twoLineTitle: (LocalizedStringKey, LocalizedStringKey)? = nil,
                                                 tint: Color,
                                                 action: @escaping () -> Void,
                                                 @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon()
                if let twoLineTitle {
                    VStack(spacing: 0) {
                        Text(twoLineTitle.0)
                        Text(twoLineTitle.1)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                } else {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(minWidth: 58)
            .frame(width: fixedWidth)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .tint(tint)
    }

    private var checkTwoLineTitle: (LocalizedStringKey, LocalizedStringKey)? {
        if fontScale == .large || fontScale == .xLarge {
            return ("check.label", allItemsChecked ? "check.off.state" : "check.on.state")
        }
        return nil
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

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
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
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                // AI生成用シートを表示（設定画面から移動）
                showAiCreateSheet = true
                GALogger.log(.function(name: "pack_edit", option: "tap_ai_create"))
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    //.imageScale(.large)
                        .symbolRenderingMode(.hierarchical)
                    Text("chappy")
                        .font(.body.weight(.regular))
                }
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showAiCreateSheet) {
                // AI生成シート本体へ現在のパックを渡し、AIが修正しやすいようにする
                ChappySheetView(basePack: pack)
                    .appFontScale(fontScale)
                    .presentationDetents([.height(ChappySheetView_HEIGHT), .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// チェック・トグルが遅延する場合があるのでプログレス付きで開始する
    ///  起動初期にDB遅延が発生して無反応に見えるためタスク化して終了を待つ
    private func startCheckToggle() {
        // 連打による状態不整合を避けるため、進行中は何もしない
        if isTogglingCheck { return }
        isTogglingCheck = true

        Task { @MainActor in
            defer {
                // 処理完了後にスピナーを消す
                isTogglingCheck = false
            }
            // 従来どおり、現在の全チェック状態からON/OFFを切り替える
            updateChecks(checked: !allItemsChecked)
        }
    }

    /// 配下の全item.checkを指定状態へ揃える。.stockは設定に応じて連動する
    private func updateChecks(checked: Bool) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        let items = pack.child.flatMap { $0.child }
        for item in items {
            if checked {
                // OFF --> ON
                item.check = (0 < item.need)
                // チェックと在庫数を連動させる
                if linkCheckWithStock {
                    item.stock = item.need
                }
            }else{
                // ON --> OFF
                item.check = false
                if linkCheckOffWithZero {
                    // チェック解除時の在庫クリアは新フラグで管理
                    item.stock = 0
                }
            }
        }
    }
    
    /// Packを.packlinファイルにして共有(Export)する
    private func exportPack() {
        do {
            cleanupShareResource()

            let dto = pack.exportRepresentation()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(dto)
            // ファイル名を使用可能文字に制限する
            let fileName = sanitizedFileName(from: pack.name.isEmpty
                                             ? pack.id : pack.name )
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName)
                .appendingPathExtension(PACK_FILE_EXTENSION)

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
