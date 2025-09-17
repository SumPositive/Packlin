//
//  ContentView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData


struct PackListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var listID = UUID() // Listリフレッシュ用
    @State private var editingPack: M1Pack?
    @State private var popupAnchor: CGPoint?

    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]

    private let rowHeight: CGFloat = 44
    
    var body: some View {
        ZStack {
            List {
                ForEach(packs) { pack in
                    ZStack {
                        PackRowView(pack: pack) { selected, point in
                            editingPack = selected
                            popupAnchor = point
                        }

                        HStack(spacing: 0) {
                            Spacer()
                            NavigationLink(value: AppDestination.groupList(packID: pack.id)) {
                                Color.clear
                            }
                            .frame(width: 180)
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .background(Color.clear).contentShape(Rectangle()) //タップ領域
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .onMove(perform: movePack)
                .environment(\.editMode, .constant(.active))
            }
            .listStyle(.plain)
            .id(listID)   // listIDが変わるとListが作り直される
            .padding(.top, -8) // headerとPackList間の余白を無くす
            .padding(.horizontal, 0)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button {
                        // Setting
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .padding(.horizontal, 8)
                    
                    Spacer()

                    Button {
                        withAnimation {
                            modelContext.undoManager?.undo()
                        }
                        listID = UUID()  // ここで List を再描画
                        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo)
                    .padding(.horizontal, 8)

                    Text("モチメモ")

                    Button {
                        withAnimation {
                            modelContext.undoManager?.redo()
                        }
                        listID = UUID()  // ここで List を再描画
                        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo)
                    .padding(.horizontal, 8)
                    
                    Spacer()

                    Button { addPack() }
                    label: {
                        Image(systemName: "plus.message")
                    }
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
                PopupView(
                    anchor: popupAnchor,
                    onDismiss: {
                        editingPack = nil
                        popupAnchor = nil
                    }
                ) {
                    EditPackView(pack: pack)
                }
                .zIndex(1)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var pack: M1Pack
    @FocusState private var nameIsFocused: Bool
    
    var body: some View {
        VStack {
            HStack {
                Text("名称")
                    .font(.caption)
                TextEditor(text: $pack.name)
                    .onChange(of: pack.name) { newValue, oldValue in
                        // 最大文字数制限
                        if APP_MAX_NAME_LEN < newValue.count {
                            pack.name = String(newValue.prefix(APP_MAX_NAME_LEN))
                        }
                    }
                    .focused($nameIsFocused) // フォーカス状態とバインド
                    .frame(height: 60)
            }
            HStack {
                Text("メモ")
                    .font(.caption)
                TextEditor(text: $pack.memo)
                    .onChange(of: pack.memo) { newValue, oldValue in
                        // 最大文字数制限
                        if APP_MAX_MEMO_LEN < newValue.count {
                            pack.memo = String(newValue.prefix(APP_MAX_MEMO_LEN))
                        }
                    }
                    .frame(height: 60)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 300, height: 150)
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
}


#Preview {
    PackListView()
}
