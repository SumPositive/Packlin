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
    @EnvironmentObject private var history: UndoStackService

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    @AppStorage(AppStorageKey.footerMessage) private var footerMessage: Bool = true

    @State private var editingPack: M1Pack?
    @State private var popupAnchor: CGPoint?
    @State private var isShowSetting: Bool = false

    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var sortedPacks: [M1Pack]

    private let rowHeight: CGFloat = 44
    // 編集シート表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingEditSheet: Bool { editingPack != nil }

    var body: some View {
        ZStack {
            List {
                Section {
                    ForEach(sortedPacks) { pack in
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
                    // 設定
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
                    
                    // Undo
                    Button {
                        // 履歴サービスへ委譲して巻き戻す
                        history.undo(context: modelContext)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .imageScale(.small)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(!history.canUndo || isShowingEditSheet)
                    .padding(.horizontal, 16)

                    Spacer()
                    Text("app.title")
                    Spacer()
                    
                    // Redo
                    Button {
                        // 履歴サービスを用いて直前のUndoをやり直す
                        history.redo(context: modelContext)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .imageScale(.small)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                    }
                    .disabled(!history.canRedo || isShowingEditSheet)
                    .padding(.horizontal, 16)
                    
                    // 新しいパック追加
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
                                .symbolRenderingMode(.hierarchical)
                                .padding(.top, 4)
                        }
                    }
                    .disabled(isShowingEditSheet)
                    .padding(.horizontal, 8)
                }
                .tint(.primary) // ヘッダ部は.accentColorにしない
                .frame(height: rowHeight)
                .padding(.horizontal, 8)
                .background(.thinMaterial)
            }
        }
        // Pack編集はポップアップからシート表示へ移行
        .sheet(item: $editingPack) { pack in
            PackEditView(pack: pack)
                .presentationDetents([.height(580)])
                .presentationDragIndicator(.hidden)
        }
        // 設定画面もシート表示へ変更
        .sheet(isPresented: $isShowSetting) {
            SettingView()
                .presentationDetents([.height(650), .large])
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
                        Text("パック内の必要なアイテムが全てチェック済み")
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
                        Text("充足（必要数を満たしている、十分な在庫あり）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "case")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Text("不足（必要数に満たない、在庫が足りない）")
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

    private func addPack() {
        // 履歴サービスを利用して新規作成を1アクションとして記録する
        history.perform(context: modelContext) {
            let orderedPacks = Array(sortedPacks)
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
        }

    }

    /// Drag-Drop-Move
    private func movePack(from source: IndexSet, to destination: Int) {
        // 並べ替えも1アクションにまとめる
        history.perform(context: modelContext) {
            var packs = Array(sortedPacks)
            let movedIDs = Set(source.map { sortedPacks[$0].id })
            packs.move(fromOffsets: source, toOffset: destination)

            var index = 0
            while index < packs.count {
                if movedIDs.contains(packs[index].id) {
                    var end = index
                    while end + 1 < packs.count, movedIDs.contains(packs[end + 1].id) {
                        end += 1
                    }
                    assignSparseOrders(nodes: packs, range: index...end) {
                        normalizeSparseOrders(packs)
                    }
                    index = end + 1
                } else {
                    index += 1
                }
            }
        }
    }
}

/// 共有メニュー画面
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        // SwiftUIの.sheet上でUIActivityViewControllerを表示すると背景が透過してしまうため、ここで背景色を明示的に塗りつぶす
        // systemBackgroundを指定することでダークモード・ライトモード双方で自然な色になる
        controller.view.backgroundColor = UIColor.systemBackground
        // isModalInPresentationをfalseにしておき、ユーザーが上スワイプで閉じられる通常動作を維持する
        controller.isModalInPresentation = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


#Preview {
    PackListView()
    //    EditPackView(pack: M1Pack(name: "TEST"))
}

