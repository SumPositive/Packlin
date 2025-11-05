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
    @AppStorage(AppStorageKey.footerMessage) private var footerMessage: Bool = true

    @State private var canUndo = false
    @State private var canRedo = false
    @State private var editingPack: M1Pack?
    @State private var popupAnchor: CGPoint?
    @State private var isShowSetting: Bool = false

    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var packs: [M1Pack]

    private let rowHeight: CGFloat = 44
    // 編集シート表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingEditSheet: Bool { editingPack != nil }

    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(packs) { pack in
                        ZStack {
                            PackRowView(pack: pack) { selected, point in
                                // Pack行のタップ位置はシートでは使用しないが、今後の拡張に備えて保持
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
                    if footerMessage {
                        // フッター：操作説明、アイコン説明
                        FooterView()
                    }
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
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 3.0))) // 回転
                    }
                    .disabled(isShowingEditSheet)
                    .padding(.horizontal, 8)
                    
                    Button {
                        canUndo = false
                        modelContext.undoManager?.performUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(!canUndo || isShowingEditSheet)
                    .padding(.horizontal, 16)

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
                    .disabled(!canRedo || isShowingEditSheet)
                    .padding(.horizontal, 16)
                    
                    Button {
                        addPack()
                    }
                    label: {
                        Image(systemName: "cross.case")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(isShowingEditSheet)
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
            //(ZStack) 設定用ポップアップを表示
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
        // Pack編集はポップアップからシート表示へ移行
        .sheet(item: $editingPack) { pack in
            PackEditView(pack: pack) {
                // onClose発火時にシートを閉じる
                editingPack = nil
                popupAnchor = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "case")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("packList.footer.outOfStock")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.secondary)
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

        let orderedPacks = Array(packs)
        let insertionIndex: Int = {
            switch insertionPosition {
            case .head:
                return 0
            case .tail:
                return orderedPacks.count
            }
        }()

        let newOrder = sparseOrderForInsertion(items: orderedPacks, index: insertionIndex) {
            normalizeSparseOrders(orderedPacks)
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

        // 追加直後に編集ポップアップを開き、すぐに名前を入力してもらう
        editingPack = newPack
        popupAnchor = nil

        NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
    }

    private func movePack(from source: IndexSet, to destination: Int) {
        // Undo grouping BEGIN
        modelContext.undoManager?.groupingBegin()
        defer {
            // Undo grouping END
            modelContext.undoManager?.groupingEnd()
        }

        var items = Array(packs)
        let movedIDs = Set(source.map { packs[$0].id })
        items.move(fromOffsets: source, toOffset: destination)

        var index = 0
        while index < items.count {
            if movedIDs.contains(items[index].id) {
                var end = index
                while end + 1 < items.count, movedIDs.contains(items[end + 1].id) {
                    end += 1
                }
                assignSparseOrders(items: items, range: index...end) {
                    normalizeSparseOrders(items)
                }
                index = end + 1
            } else {
                index += 1
            }
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

