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
                Section {
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
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .onMove(perform: movePack)
                }
                footer: {
                    // フッター：操作説明、アイコン説明
                    FooterView()
                        .listRowSeparator(.hidden) // 下線なし
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            // 区切り線は、Rowの.overlayで表示している
            .padding(.horizontal, 0)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button {
                        // Setting
                        popupAnchor = nil // 中央
                        isShowSetting = true
                    } label: {
                        if #available(iOS 18.0, *) {
                            Image(systemName: "gearshape")
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 3.0))) // 回転
                        } else {
                            Image(systemName: "gearshape")
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        }
                    }
                    .disabled(isShowingPopup)
                    .padding(.horizontal, 8)
                    
                    Button {
                        canUndo = false
                        modelContext.undoManager?.performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(!canUndo || isShowingPopup)
                    .padding(.horizontal, 8)

                    Spacer()
                    Text("app.title")
                    Spacer()
                    
                    Button {
                        canRedo = false
                        modelContext.undoManager?.performRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(!canRedo || isShowingPopup)
                    .padding(.horizontal, 8)
                    
                    Button {
                        addPack()
                    }
                    label: {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            Image(systemName: "plus")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                .padding(.top, 4)
                        }
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

    /// フッター：操作説明、アイコン説明
    struct FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("packList.footer.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Group {
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            Image(systemName: "checkmark")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                .padding(.top, 4)
                        }
                        Text("packList.footer.checked")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            Image(systemName: "circle")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                                .padding(.top, 4)
                        }
                        Text("packList.footer.inStock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "case")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("packList.footer.outOfStock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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

    private func addPack() {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
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

        // 新規モチメモ作成時に初期グループとアイテムを1つずつ追加する
        let initialGroup = M2Group(name: "", order: 0, parent: newPack)
        modelContext.insert(initialGroup)
        newPack.child.append(initialGroup)

        let initialItem = M3Item(name: "", order: 0, parent: initialGroup)
        modelContext.insert(initialItem)
        initialGroup.child.append(initialItem)

        let descriptor = FetchDescriptor<M1Pack>()
        if let allPacks = try? modelContext.fetch(descriptor) {
            M1Pack.normalizePackOrder(allPacks)
        }
    }

    private func movePack(from source: IndexSet, to destination: Int) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
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

