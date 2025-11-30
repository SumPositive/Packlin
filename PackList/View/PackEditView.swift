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

    @FocusState private var nameIsFocused: Bool

    @State private var shareURL: URL?
    @State private var isPresentingShare = false
    @State private var showAiCreateSheet = false
    
    private var allItemsChecked: Bool {
        let items = pack.child.flatMap { $0.child }
        return !items.isEmpty && items.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("パック編集") {
                    HStack {    // Actions
                        // チェックON/OFF
                        Button {
                            // チェック・トグル；配下の全item.checkを反転する。.stockはそのまま
                            checkToggle()
                        } label: {
                            VStack {
                                ZStack {
                                    Image(systemName: "case")
                                        .imageScale(.large)
                                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                        .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
                                    
                                    if allItemsChecked {
                                        Image(systemName: "checkmark")
                                            .imageScale(.small)
                                            .padding(.top, 4)
                                    }
                                }
                                if allItemsChecked {
                                    Text("全✔︎ON→OFF")
                                        .font(.caption)
                                }else{
                                    Text("OFF→全✔︎ON")
                                        .font(.caption)
                                }
                            }
                        }
                        .frame(width: 88) // on/off変化時に幅が変わらないように
                        .tint(.purple)
                        .padding(.horizontal, 8)
                        
                        // 複製
                        Button {
                            pack.duplicate()
                        } label: {
                            VStack {
                                Image(systemName: "plus.square.on.square")
                                    .imageScale(.large)
                                Text("複製")
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
                                Image(systemName: "square.and.arrow.up")
                                    .imageScale(.large)
                                Text("共有・保存")
                                    .font(.caption)
                            }
                        }
                        .tint(.accentColor)
                        .padding(.leading, 16)
                        
                        Spacer()
                        
                        // 削除
                        Button {
                            // シートを強制的に閉じてから削除処理へ進める
                            dismiss()
                            // Packを削除する
                            pack.delete()
                        } label: {
                            VStack {
                                Image(systemName: "trash")
                                    .imageScale(.large)
                                Text("削除")
                                    .font(.caption)
                            }
                        }
                        .tint(.red)
                        .padding(.horizontal, 8)
                    }
                    // Form配下ではセル全体にボタン用のハイライトプレートが載り、
                    // そのままだと各Buttonが同じ行に並んでいてもセル全体が同一の大きなボタンのように扱われてしまう。
                    // これが原因で一度のタップが複数のButtonへ伝播し、同時にアクションが実行される状態になっていた。
                    // BorderlessButtonStyleを適用するとセル全体のボタン化が解除され、
                    // それぞれのButtonが独立したタップ領域として機能するようになる。
                    .buttonStyle(BorderlessButtonStyle())
                }

                Section("パック名") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $pack.name)
                            .font(FONT_EDIT)
                            .onChange(of: pack.name) { oldValue, newValue in
                                // 最大文字数制限（向きは < で統一）
                                if APP_MAX_NAME_LEN < newValue.count {
                                    pack.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                                }
                            }
                            .focused($nameIsFocused) // フォーカス状態とバインド
                        
                        if pack.name.isEmpty {
                            // 名前未入力時のガイド文を表示（TextEditorはプレースホルダー未対応のため）
                            Text("新しいパックの名前を入れてください")
                                .foregroundStyle(.secondary)
                                .padding(.top, 20)
                                .padding(.horizontal, 16)
                                .allowsHitTesting(false) // プレースホルダーをタップしてもフォーカスが当たるように
                        }
                    }
                    .frame(height: 80)
                }
                
                Section("メモ") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $pack.memo)
                            .font(FONT_MEMO)
                            .onChange(of: pack.memo) { oldValue, newValue in
                                // 最大文字数制限（こちらも < の形で統一）
                                if APP_MAX_MEMO_LEN < newValue.count {
                                    pack.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                                }
                            }
                    }
                    .frame(height: 140)
                }
            }
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
        }
        .onDisappear() {
            // 末尾のスペースと改行を除去
            pack.name = pack.name.trimTrailSpacesAndNewlines
            pack.memo = pack.memo.trimTrailSpacesAndNewlines
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
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
                    Text("チャッピー")
                        .font(.body.weight(.regular))
                }
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showAiCreateSheet) {
                // AI生成シート本体へ現在のパックを渡し、AIが修正しやすいようにする
                AiCreateSheetView(basePack: pack)
                    .presentationDetents([.height(AiCreateSheetView_HEIGHT), .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    /// チェック・トグル；配下の全item.checkを反転する。.stockはそのまま
    private func checkToggle() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        let toggle = allItemsChecked
        let items = pack.child.flatMap { $0.child }
        for item in items {
            if toggle {
                // ON --> OFF
                item.check = false
                // チェックと在庫数を連動させる
                if linkCheckWithStock {
                    item.stock = 0
                }
            }else{
                // OFF --> ON
                item.check = (0 < item.need)
                // チェックと在庫数を連動させる
                if linkCheckWithStock {
                    item.stock = item.need
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

