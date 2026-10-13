//
//  ItemDetailSheet.swift
//  PackList
//
//  タグ式のアイテム縦覧で、アイテムをタップしたときに開くシート
//  - 小さい状態：名称・メモ・タグを表示し、個重量・在庫数・必要数はここで編集できる（左上で閉じ、右上か上へのスワイプで広がる）
//  - 広げた状態：アイテム詳細（ItemEditView）をそのまま出して、全部を編集できる
//

import SwiftUI
import SwiftData

struct ItemDetailSheet: View {
    let pack: M1Pack
    /// 前へ・次へでたどる並び（縦覧の表示順）
    let adjacentItemProvider: (M3Item, Int) -> M3Item?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKey.displayMode) private var displayMode: DisplayMode = .default

    /// 表示中のアイテム（広げた状態の前へ・次へで切り替わる）
    @State private var currentItem: M3Item
    @State private var detent: PresentationDetent = .height(240)
    /// 小さい状態の中身の実測高さ（0 は未測定）
    @State private var summaryHeight: CGFloat = 0

    /// 測っていない部分の高さ（シート上端のつまみまわりの余白）
    private let chromeHeight: CGFloat = 24

    /// 最初から広げて開くか（新しいアイテムを追加したとき）
    private let startsExpanded: Bool
    /// 前へ・次へで表示中のアイテムが変わったとき（一覧の強調表示を追従させる）
    private let onCurrentItemChange: (M3Item) -> Void

    init(pack: M1Pack,
         item: M3Item,
         startsExpanded: Bool = false,
         adjacentItemProvider: @escaping (M3Item, Int) -> M3Item?,
         onCurrentItemChange: @escaping (M3Item) -> Void = { _ in }) {
        self.onCurrentItemChange = onCurrentItemChange
        self.pack = pack
        self.startsExpanded = startsExpanded
        self.adjacentItemProvider = adjacentItemProvider
        self._currentItem = State(initialValue: item)
        self._detent = State(initialValue: startsExpanded ? .large : .height(240))
    }

    /// 小さい状態の高さ。中身が分かるまでは目安の 240 で開く
    private var summaryDetent: PresentationDetent {
        guard 0 < summaryHeight else { return .height(240) }
        return .height(min(summaryHeight + chromeHeight, UIScreen.main.bounds.height * 0.6))
    }

    private var isExpanded: Bool { detent == .large }

    var body: some View {
        Group {
            if isExpanded, let group = currentItem.parent {
                // 広げた状態：アイテム詳細をそのまま使う（閉じる・削除・複製でシートを閉じる）
                ItemEditView(
                    pack: pack,
                    group: group,
                    item: currentItem,
                    onDismiss: { dismiss() },
                    onSelectItem: { selected in
                        currentItem = selected
                        onCurrentItemChange(selected)
                    },
                    adjacentItemProvider: adjacentItemProvider,
                    isInSheet: true
                )
            } else {
                summary
            }
        }
        .presentationDetents([summaryDetent, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: summaryDetent) { oldValue, newValue in
            // 中身の高さが測れたら、小さい状態の高さを追従させる
            if detent == oldValue {
                detent = newValue
            }
        }
        .onAppear {
            if !startsExpanded {
                detent = summaryDetent
            }
        }
    }

    // MARK: - 小さい状態（表示のみ）

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 左上の下向きボタンで閉じ、右上の上向きボタンで広げる。間に名称、メモがあれば名称の下に出す
            HStack(alignment: .top, spacing: 12) {
                circleButton(systemImage: "chevron.down",
                             accessibilityLabel: "close.sheet") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 4) {
                    currentItem.name.placeholderText("new.item")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(currentItem.name.isEmpty ? .secondary : .primary)
                        .lineLimit(3)
                    if !currentItem.memo.isEmpty {
                        Text(currentItem.memo)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 名称はボタンの中央の高さに揃える
                .padding(.top, 4)
                .contentShape(Rectangle())
                .onTapGesture(perform: expand)

                VStack(spacing: 4) {
                    circleButton(systemImage: "chevron.up",
                                 accessibilityLabel: "item.sheet.expand",
                                 action: expand)
                    // 初心者には何が開くかを添える
                    if displayMode == .beginner {
                        Text("item.sheet.detail.edit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 64)
                            .cappedAtLargeFontSize()
                    }
                }
            }

            // 個重量・在庫数・必要数は、小さい状態でもここで編集できる（アイテム詳細と同じ部品）
            // ここには広げるタップを付けない（ステッパなどの操作を妨げないため）
            ItemQuantityEditor(item: currentItem)

            // タグ（付いているものだけを並べる）
            if !currentItem.tags.isEmpty {
                AZFlowLayout(spacing: 6, rowSpacing: 6, alignment: .leading) {
                    ForEach(currentItem.tags, id: \.self) { tag in
                        TagChip(title: tag, isSelected: true) {}
                    }
                }
                .allowsHitTesting(false)
                .cappedAtLargeFontSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: expand)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            guard 0 < height else { return }
            summaryHeight = height
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // 余白のタップでも広げる（名称・タグは上で個別に受ける）
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: expand)
        }
    }

    /// 左上（閉じる）・右上（広げる）の丸ボタン
    private func circleButton(systemImage: String,
                              accessibilityLabel: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        SheetCircleButton(systemImage: systemImage, accessibilityLabel: accessibilityLabel, action: action)
    }

    /// 広げて全部を編集できるようにする
    private func expand() {
        withAnimation(.easeInOut(duration: 0.25)) {
            detent = .large
        }
    }
}

/// シート左上・右上に置く丸ボタン（アイテムシートと、シート内のアイテム詳細で共通のデザイン）
struct SheetCircleButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
