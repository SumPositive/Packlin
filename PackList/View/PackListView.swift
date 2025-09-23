//
//  ContentView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit


struct PackListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var listID = UUID() // Listリフレッシュ用
    @State private var editingPack: M1Pack?
    @State private var popupAnchor: CGPoint?
    @State private var isShowSetting: Bool = false

    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]

    private let rowHeight: CGFloat = 44
    // Popup表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingPopup: Bool { editingPack != nil }

    var body: some View {
        ZStack {
            List {
                ForEach(packs) { pack in
                    ZStack {
                        PackRowView(pack: pack) { selected, point in
                            editingPack = selected
                            popupAnchor = point
                        }

                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                Spacer()
                                NavigationLink(value: AppDestination.groupList(packID: pack.id)) {
                                    Color.clear
                                }
                                .buttonStyle(.plain)
                                .frame(width: geo.size.width/2.0) // 画面右半分タップでナビ遷移
                                .contentShape(Rectangle()) //タップ領域
                                .background(Color.clear)
                                .padding(.trailing, 8)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .onMove(perform: movePack)
                .environment(\.editMode, .constant(.active))
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden) // 区切り線は、Rowの.overlayで表示している
            .id(listID)   // listIDが変わるとListが作り直される
            .padding(.top, -8) // headerとPackList間の余白を無くす
            .padding(.horizontal, 0)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button {
                        // Setting
                        popupAnchor = nil // 中央
                        isShowSetting = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .disabled(isShowingPopup)
                    .padding(.horizontal, 8)
                    
                    Button {
                        withAnimation {
                            modelContext.undoManager?.undo()
                        }
                        listID = UUID()  // ここで List を再描画
                        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo || isShowingPopup)
                    .padding(.horizontal, 8)

                    Spacer()
                    Text("app.title")
                    Spacer()
                    
                    Button {
                        withAnimation {
                            modelContext.undoManager?.redo()
                        }
                        listID = UUID()  // ここで List を再描画
                        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo || isShowingPopup)
                    .padding(.horizontal, 8)
                    
                    Button { addPack() }
                    label: {
                        Image(systemName: "plus.message")
                    }
                    .disabled(isShowingPopup)
                    .padding(.horizontal, 8)
                }
                .frame(height: rowHeight)
                .padding(.horizontal, 8)
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
            if let pack = editingPack {
                PopupView(anchor: popupAnchor) {
                    editingPack = nil
                    popupAnchor = nil
                } content: {
                    EditPackView(pack: pack) {
                        //.onClose：内から閉じる場合
                        editingPack = nil
                        popupAnchor = nil
                    }
                }
                .zIndex(1)
            }
            //----------------------------------
            //(ZStack 2) Popupで表示
            if isShowSetting {
                PopupView(
                    anchor: popupAnchor,
                    onDismiss: {
                        isShowSetting = false
                    }
                ) {
                    SettingView()
                }
                .zIndex(2)
            }
        }
    }

    private func updateUndoRedo() {
        if let um = modelContext.undoManager {
            canUndo = um.canUndo
            canRedo = um.canRedo
        }
    }

    private func addPack() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        let newPack = M1Pack(name: "", order: M1Pack.nextPackOrder(packs))
        modelContext.insert(newPack)
    }

    private func movePack(from source: IndexSet, to destination: Int) {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            updateUndoRedo()
        }

        var items = packs
        items.move(fromOffsets: source, toOffset: destination)
        for (index, pack) in items.enumerated() {
            pack.order = index
        }
    }
}


struct EditPackView: View {
    @Bindable var pack: M1Pack
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var nameIsFocused: Bool
    @State private var shareURL: URL?
    @State private var isPresentingShare = false
    
    var body: some View {
        VStack {
            HStack {    // Actions
                Button {
                    duplicatePack()
                } label: {
                    VStack {
                        Image(systemName: "plus.square.on.square")
                        Text("action.duplicate")
                            .font(.caption)
                    }
                }
                .tint(.accentColor)
                .padding(.horizontal, 8)

                Spacer()

                Button {
                    exportPack()
                } label: {
                    VStack {
                        Image(systemName: "arrow.up.message")
                        Text("action.json.upload")
                            .font(.caption)
                    }
                }
                .tint(.accentColor)
                .padding(.horizontal, 8)
                
                //Text("Pack.edit.title").font(.footnote)
                Spacer()

                Button {
                    // EditItemViewを閉じる
                    onClose()
                    // Itemを削除する
                    deletePack()
                } label: {
                    VStack {
                        Image(systemName: "trash")
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
                .onChange(of: pack.name) { newValue, oldValue in
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
                .onChange(of: pack.memo) { newValue, oldValue in
                    // 最大文字数制限
                    if APP_MAX_MEMO_LEN < newValue.count {
                        pack.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                    }
                }
                .frame(height: 80)

            Text("edit.info.swipeToDismiss")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .frame(width: 320, height: 284)
        .sheet(isPresented: $isPresentingShare, onDismiss: cleanupShareResource) {
            if let shareURL {
                ActivityView(activityItems: [shareURL])
            }
        }
        .onAppear {
            // UndoGrouping
            modelContext.undoManager?.beginUndoGrouping()
            if pack.name.isEmpty {
                nameIsFocused = true
            }
        }
        .onDisappear() {
            // 末尾のスペースと改行を除去
            pack.name = pack.name.trimTrailSpacesAndNewlines
            pack.memo = pack.memo.trimTrailSpacesAndNewlines
            // UndoGrouping
            if let um = modelContext.undoManager, 0 < um.groupingLevel {
                um.endUndoGrouping()
            }
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
        }
    }
    
    /// 現在のPackを複製して現在行に追加する
    private func duplicatePack() {
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
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
        modelContext.undoManager?.beginUndoGrouping()
        defer {
            modelContext.undoManager?.endUndoGrouping()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
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

/// 共有メニュー画面
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


#Preview {
    PackListView()
    //    EditPackView(pack: M1Pack(name: "TEST"))
}

