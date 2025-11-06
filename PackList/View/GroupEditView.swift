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
    @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = false

    @FocusState private var nameIsFocused: Bool

    private var allItemsChecked: Bool {
        !group.child.isEmpty && group.child.allSatisfy { $0.check || $0.need == 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(group.name.isEmpty ? String(localized:"新しいグループ") : group.name) {
                    HStack {    // Actions
                        // チェックON/OFF
                        Button {
                            // チェック・トグル；配下の全item.checkを反転する。.stockはそのまま
                            checkToggle()
                        } label: {
                            VStack {
                                if allItemsChecked {
                                    Image(systemName: "square")
                                        .imageScale(.large)
                                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                        .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
                                    
                                    Text("全チェックOFF")
                                        .font(.caption)
                                }else{
                                    Image(systemName: "checkmark.square")
                                        .imageScale(.large)
                                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                        .symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
                                    
                                    Text("全チェックON")
                                        .font(.caption)
                                }
                            }
                        }
                        .frame(width: 88) // on/off変化時に幅が変わらないように
                        .tint(.purple)
                        .padding(.horizontal, 8)
                        
                        // 複製
                        Button {
                            group.duplicate()
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
                        
                        Spacer()
                        
                        // 削除
                        Button {
                            // シートを閉じてから削除処理を行う
                            dismiss()
                            group.delete()
                        } label: {
                            VStack {
                                Image(systemName: "trash")
                                    .imageScale(.large)
                                //.symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                //.symbolEffect(.breathe.pulse.byLayer, options: .nonRepeating) // Once
                                
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
                Section("グループ名") {
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
                }
                Section("メモ") {
                    TextEditor(text: $group.memo)
                        .font(FONT_MEMO)
                        .onChange(of: group.memo) { oldValue, newValue in
                            // 最大文字数制限
                            if APP_MAX_MEMO_LEN < newValue.count {
                                group.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                            }
                        }
                        .frame(height: 140)
                }
                .padding(.top, -20)
            }
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
        let items = group.child
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

}

