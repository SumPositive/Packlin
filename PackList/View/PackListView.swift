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
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var history: UndoStackService

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    // 表示モード（初心者／上級者）をAppStorageで永続化
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default
    @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .default

    @State private var editingPack: M1Pack?
    @State private var popupAnchor: CGPoint?
    @State private var isShowSetting: Bool = false
    @State private var isShowAiCreateSheet: Bool = false

    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var sortedPacks: [M1Pack]

    private let rowHeight: CGFloat = 44
    // 初心者モードかどうかでヘッダーの説明を出し分ける
    private var isBeginnerMode: Bool { displayMode == .beginner }
    // ヘッダーの高さを表示モードで変える
    private var headerHeight: CGFloat { isBeginnerMode ? APP_HEADER_HEIGHT_BEG : APP_HEADER_HEIGHT_EXP }
    // 編集シート表示中はナビバーボタンを非活性にするためのフラグ
    private var isShowingEditSheet: Bool { editingPack != nil }
    // シート表示時は自動モードも現在の外観へ解決して渡し、切り替え反映の遅れを避ける
    private var settingSheetColorScheme: ColorScheme? {
        appearanceMode.colorScheme ?? colorScheme
    }

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
                    if isBeginnerMode {
                        // 表示モードが初心者なら補足説明をフッターに表示する
                        FooterView()
                            .listRowSeparator(.hidden) // 下線なし
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            // 区切り線は、Rowの.overlayで表示している
            .padding(.horizontal, 0)
            .safeAreaInset(edge: .top) { // ヘッダ部
                HStack {
                    // 設定ボタンと説明
                    VStack(spacing: 6) {
                        Button {
                            // Setting
                            popupAnchor = nil // 中央
                            isShowSetting = true
                        } label: {
                            Image(systemName: "gearshape")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 3.0))) // 回転
                        }
                        .buttonStyle(.borderless)
                        .disabled(isShowingEditSheet)

                        if isBeginnerMode {
                            // 初心者向け：ボタンの役割をテキストで補足
                            Text("設定を開く")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 50)
                    .padding(.horizontal, 6)

                    // Undoボタンと説明
                    VStack(spacing: 6) {
                        Button {
                            // 履歴サービスへ委譲して巻き戻す
                            history.undo(context: modelContext)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        }
                        .buttonStyle(.borderless)
                        .disabled(!history.canUndo || isShowingEditSheet)

                        if isBeginnerMode {
                            // 初心者向け：巻き戻し操作の説明
                            Text("直前の変更を元に戻す")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: 55)
                    .padding(.horizontal, 6)

                    Spacer()

                    // タイトル表示は見出しとして常に同じ大きさで見せたいので、Dynamic Typeの拡大縮小に左右されない固定サイズを指定
                    Text("app.title")
                        .font(.system(size: 15))
                        .lineLimit(1)
                        .frame(minWidth: 50)

                    Spacer()

                    // Redoボタンと説明
                    VStack(spacing: 6) {
                        Button {
                            // 履歴サービスを用いて直前の変更にやり直す
                            history.redo(context: modelContext)
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        }
                        .buttonStyle(.borderless)
                        .disabled(!history.canRedo || isShowingEditSheet)

                        if isBeginnerMode {
                            // 初心者向け：Redoの役割を説明
                            Text("戻した変更をやり直す")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: 55)
                    .padding(.horizontal, 6)

                    // 新しいパック追加と説明
                    VStack(spacing: 6) {
                        // メニューからAI依頼と手動作成を選べるようにする
                        Menu {
                            Button {
                                // チャッピー(AI)に新しいパックを作ってもらうフローへ誘導
                                isShowAiCreateSheet = true
                            } label: {
                                Label("チャッピー(AI)に作ってもらう", systemImage: "sparkles")
                            }
                            
                            Button {
                                // これまで通り自分で項目を入力して作成するパターン
                                addPack()
                            } label: {
                                Label("自分で作る", systemImage: "hand.tap")
                            }
                        } label: {
                            ZStack {
                                Image(systemName: "case")
                                    .imageScale(.large)
                                    .symbolRenderingMode(.hierarchical)
                                Image(systemName: "plus")
                                    .imageScale(.small)
                                    .symbolRenderingMode(.hierarchical)
                                    .padding(.top, 4)
                            }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .disabled(isShowingEditSheet)

                        if isBeginnerMode {
                            // 初心者向け：新規パック追加の説明
                            Text("新しいパックを追加する")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 66)
                    .padding(.horizontal, 6)
                }
                // iPadのマルチウィンドウで左上のシステムアイコンに隠れないよう、ヘッダー全体を右へずらす
                .padding(.leading, ipadWindowControlInset())
                .tint(.primary) // ヘッダ部は.accentColorにしない
                .frame(height: headerHeight)
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
                .preferredColorScheme(settingSheetColorScheme)
                .presentationDetents([.height(SettingView_HEIGHT), .large])
                .presentationDragIndicator(.visible)
        }
        // 初心者モード時のAI新規作成メニューから遷移するシート
        .sheet(isPresented: $isShowAiCreateSheet) {
            ChappySheetView()
                .presentationDetents([.height(ChappySheetView_HEIGHT), .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// フッター：ボタンの説明
    struct FooterView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("パックの状態")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                Group {
                    HStack(spacing: 8) {
                        Image(systemName: "case")
                            .imageScale(.large)
                        Text("不足（必要数に満たない、在庫が足りない）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                            Image(systemName: "circle")
                                .imageScale(.small)
                                .padding(.top, 4)
                        }
                        Text("充足（必要数を満たしている、十分な在庫あり）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "case")
                                .imageScale(.large)
                            Image(systemName: "checkmark")
                                .imageScale(.small)
                                .padding(.top, 4)
                        }
                        Text("✔︎済（パック内の必要なアイテムが全てチェック済み）")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)

                Text("現在、「初心者」表示モードです。設定から「達人」を選択すれば、ほぼアイコンだけの達人表示に変わります")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
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
