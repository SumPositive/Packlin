//
//  ItemTagViews.swift
//  PackList
//
//  アイテムのタグ選択（アイテム詳細）と、タグの丸ボタン（アイテム縦覧の絞り込みと共用）
//  タグは独立したデータを持たず、パック内のアイテムに付いているものを集めて一覧にする
//

import SwiftUI

/// タグの丸ボタン。選択中は背景と枠をタグ色（COLOR_TAG）にする
struct TagChip: View {
    let title: String
    let isSelected: Bool
    var isDisabled: Bool = false
    /// 「タグなし」など普通のタグと区別したいボタン（文字を控えめにし、背景を薄いグレーにする）
    var isSpecial: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var borderColor: Color {
        // ダークでは背景が暗くタグ色が沈むので、枠を濃くする
        return isSelected ? COLOR_TAG.opacity(colorScheme == .dark ? 0.9 : 0.62) : Color.secondary.opacity(0.25)
    }

    /// 選択中の塗り。ダークでは薄い塗りだとくすんで見えるので、濃いめにして明るく見せる
    private var selectedFill: Color {
        COLOR_TAG.opacity(colorScheme == .dark ? 0.32 : 0.14)
    }

    private var chipLabel: some View {
        // 選択中も文字は太字にしない（幅が変わると折り返しの詰め込みが組み直され、並びが入れ替わる）
        // 選択は背景・枠のタグ色と、濃いタグ色の文字で示す
        Text(title)
            .font(.subheadline)
            .foregroundStyle(isSelected ? COLOR_TAG_TEXT : (isSpecial ? Color.secondary : Color.primary))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? selectedFill
                          : (isSpecial ? Color(.secondarySystemBackground) : Color(.systemBackground)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Capsule())
    }

    var body: some View {
        Button(action: action) {
            chipLabel
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// アイテム詳細の下部に置くタグ選択
/// - 上の欄で一覧を探し、一致するタグが無ければその文字で追加できる
/// - タグは複数選べる
/// - タグの名前の変更・削除は、タグ欄の「編集」から開くシート（TagManageSheet）で行う
struct ItemTagEditor: View {
    let pack: M1Pack
    @Bindable var item: M3Item
    var backgroundColor: Color = COLOR_BACK_INPUT
    var cornerRadius: CGFloat = 12
    /// 入力欄からタグ一覧の2行目までを覆う目印の ID（親の画面がここまでスクロールして、キーボードの上に見せる）
    var scrollAnchorID: String? = nil
    /// タグの入力欄にフォーカスが入った／外れたとき（親の画面が検索結果の見える位置へスクロールするため）
    var onSearchFocusChange: (Bool) -> Void = { _ in }

    @State private var searchText: String = ""
    /// タグ一覧の上端（この枠の中の位置）と、タグ1つの高さ。スクロールの目印の高さを決めるために測る
    @State private var tagListTop: CGFloat = 0
    @State private var tagChipHeight: CGFloat = 0
    /// 表示するタグ一覧（縦覧のタグ一覧と同じ指定順）
    /// 選択を外したタグがその場で一覧から消えず、押すたびに並びが動かないよう、開いた時点の一覧を保持して追加分を末尾に足していく
    @State private var knownTags: [String] = []
    @FocusState private var isSearchFocused: Bool

    private var keyword: String {
        String(searchText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(APP_MAX_TAG_LEN))
    }

    private var visibleTags: [String] {
        guard !keyword.isEmpty else { return knownTags }
        return knownTags.filter { $0.localizedCaseInsensitiveContains(keyword) }
    }

    /// 入力した文字のタグがまだ無いときだけ「追加」を出す
    private var canAddKeyword: Bool {
        !keyword.isEmpty && !knownTags.contains(keyword)
    }

    private var isTagLimitReached: Bool {
        APP_MAX_ITEM_TAGS <= item.tags.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // タグを探す（無ければ追加）
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(LocalizedStringKey("tag.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($isSearchFocused)
                    .onChange(of: isSearchFocused) { _, focused in
                        onSearchFocusChange(focused)
                    }
                    .onSubmit {
                        if canAddKeyword {
                            addKeywordTag()
                        }
                    }
                // 入力した文字のタグが無いときだけ、消去ボタンの左に「追加」を出す
                if canAddKeyword {
                    Button {
                        addKeywordTag()
                    } label: {
                        Label("tag.add.button", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.borderless)
                    .disabled(isTagLimitReached)
                }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey("clear"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

            // タグ一覧。入力中は2行ぶんの高さを確保し、絞り込みで一覧が減っても枠が縮んで画面が詰まらないようにする
            VStack(alignment: .leading, spacing: 0) {
                if visibleTags.isEmpty {
                    if knownTags.isEmpty && !canAddKeyword {
                        Text("tag.empty")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // 左寄せで並べ、行末に空きがあれば後ろの収まるタグを繰り上げる（アイテム縦覧のタグ一覧と同じ）
                    AZFlowLayout(spacing: 8, rowSpacing: 8, alignment: .leading, packToFill: true) {
                        ForEach(visibleTags, id: \.self) { tag in
                            let isSelected = item.tags.contains(tag)
                            TagChip(title: tag,
                                    isSelected: isSelected,
                                    isDisabled: !isSelected && isTagLimitReached) {
                                toggle(tag)
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                tagChipHeight = height
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.coordinateSpaceName)).minY } action: { top in
                        tagListTop = top
                    }
                }
            }
            .frame(minHeight: reservedTagListHeight, alignment: .top)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
        )
        // 入力欄からタグ一覧の2行目まで（タグが無ければ枠全体）を覆う透明な目印
        .background(alignment: .top) {
            if let scrollAnchorID {
                Color.clear
                    .frame(height: scrollAnchorHeight)
                    .frame(maxHeight: scrollAnchorHeight == nil ? .infinity : nil, alignment: .top)
                    .id(scrollAnchorID)
            }
        }
        .coordinateSpace(.named(Self.coordinateSpaceName))
        // 前後のアイテムへ切り替えたときも、そのアイテムで一覧を作り直す
        .task(id: item.id) {
            searchText = ""
            reloadKnownTags()
        }
    }

    private func reloadKnownTags() {
        // 縦覧のタグ一覧と同じ指定順で出し、アイテムを切り替えても位置を変えない
        var tags = pack.tagsInManualOrder
        // パック外のアイテム（移動直後など）に付いているタグも出す
        tags.append(contentsOf: item.tags.filter { !tags.contains($0) })
        knownTags = tags
    }

    private static let coordinateSpaceName = "ItemTagEditor"

    /// 入力中にタグ一覧へ確保する高さ（2行ぶん）。入力していないときや、まだ測れていないときは nil
    private var reservedTagListHeight: CGFloat? {
        guard isSearchFocused, 0 < tagChipHeight else { return nil }
        return tagChipHeight * 2 + 8
    }

    /// スクロールの目印の高さ：タグ一覧の上端 + 2行ぶん（行間 8）+ 枠の下の余白 12
    /// タグ一覧が出ていない（測れていない）ときは nil で枠全体にする
    private var scrollAnchorHeight: CGFloat? {
        guard !visibleTags.isEmpty, 0 < tagListTop, 0 < tagChipHeight else { return nil }
        return tagListTop + tagChipHeight * 2 + 8 + 12
    }

    private func toggle(_ tag: String) {
        if let index = item.tags.firstIndex(of: tag) {
            item.tags.remove(at: index)
        } else {
            item.tags = M3Item.sanitizedTags(item.tags + [tag])
        }
    }

    /// 入力した文字でタグを作り、このアイテムに付ける
    private func addKeywordTag() {
        let tag = keyword
        guard !tag.isEmpty, !isTagLimitReached else { return }
        if !knownTags.contains(tag) {
            // 新しいタグは使っているアイテムが一番少ないので末尾に足す
            knownTags.append(tag)
        }
        if !item.tags.contains(tag) {
            item.tags = M3Item.sanitizedTags(item.tags + [tag])
        }
        searchText = ""
    }
}
