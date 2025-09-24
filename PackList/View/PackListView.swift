//
//  PackListView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
import UIKit


struct PackListView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default

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
            //.padding(.top, -8) // headerとPackList間の余白を無くす
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
                    
                    Button {
                        addPack()
                    }
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
                    PackEditView(pack: pack) {
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

        let newOrder: Int
        switch insertionPosition {
        case .head:
            let minOrder = packs.map { $0.order }.min() ?? 0
            newOrder = minOrder - 1
        case .tail:
            let maxOrder = packs.map { $0.order }.max() ?? -1
            newOrder = maxOrder + 1
        }

        let newPack = M1Pack(name: "", order: newOrder)
        modelContext.insert(newPack)

        let descriptor = FetchDescriptor<M1Pack>()
        if let allPacks = try? modelContext.fetch(descriptor) {
            M1Pack.normalizePackOrder(allPacks)
        }
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

