//
//  ItemTagViews.swift
//  PackList
//
//  アイテムのタグ選択（アイテム詳細）と、タグの丸ボタン（アイテム縦覧の絞り込みと共用）
//  タグは独立したデータを持たず、パック内のアイテムに付いているものを集めて一覧にする
//

import SwiftUI

/// タグの丸ボタン。選択中はアクセント色で塗る（設定のプルダウン候補と同じ見た目）
struct TagChip: View {
    let title: String
    let isSelected: Bool
    var isDisabled: Bool = false
    /// 名前を編集中（長押し中のタグ）
    var isEditing: Bool = false
    /// 「タグなし」など普通のタグと区別したいボタン（文字を控えめにし、背景を薄いグレーにする）
    var isSpecial: Bool = false
    /// 長押ししたときの処理。nil のときは長押しを受けない
    var onLongPress: (() -> Void)? = nil
    let action: () -> Void

    private var borderColor: Color {
        if isEditing { return Color.orange }
        return isSelected ? Color.accentColor.opacity(0.62) : Color.secondary.opacity(0.25)
    }

    private var chipLabel: some View {
        Text(title)
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.accentColor : (isSpecial ? Color.secondary : Color.primary))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16)
                          : (isSpecial ? Color(.secondarySystemBackground) : Color(.systemBackground)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: (isSelected || isEditing) ? 1.5 : 1)
            )
            .contentShape(Capsule())
    }

    var body: some View {
        Group {
            if let onLongPress {
                // タップで選択、長押しで編集。Button だと長押し後にタップも走るのでジェスチャーで分ける
                chipLabel
                    .onTapGesture {
                        guard !isDisabled else { return }
                        action()
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        onLongPress()
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: Text("tag.rename.button")) {
                        onLongPress()
                    }
            } else {
                Button(action: action) {
                    chipLabel
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// アイテム詳細の下部に置くタグ選択
/// - 上の欄で一覧を探し、一致するタグが無ければその文字で追加できる
/// - タグは複数選べる
/// - タグを長押しすると検索欄で名前を編集でき、パック内の同じタグがまとめて変わる
struct ItemTagEditor: View {
    let pack: M1Pack
    @Bindable var item: M3Item
    var backgroundColor: Color = COLOR_BACK_INPUT
    var cornerRadius: CGFloat = 12

    @State private var searchText: String = ""
    /// 表示するタグ一覧（開いた時点で、付いているタグを先頭に、それぞれアイテム数の多い順）
    /// 選択を外したタグがその場で一覧から消えず、押すたびに並びが動かないよう、開いた時点の一覧を保持して追加分を末尾に足していく
    @State private var knownTags: [String] = []
    /// 名前を編集中のタグ（長押しで設定）。nil のときは通常の検索・追加
    @State private var editingTag: String?
    @FocusState private var isSearchFocused: Bool

    private var keyword: String {
        String(searchText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(APP_MAX_TAG_LEN))
    }

    private var visibleTags: [String] {
        // 編集中は入力欄にタグ名が入るので、一覧は絞り込まずに全部出す
        guard !keyword.isEmpty, editingTag == nil else { return knownTags }
        return knownTags.filter { $0.localizedCaseInsensitiveContains(keyword) }
    }

    /// 入力した文字のタグがまだ無いときだけ「追加」を出す
    private var canAddKeyword: Bool {
        editingTag == nil && !keyword.isEmpty && !knownTags.contains(keyword)
    }

    /// 編集中で、名前が変わっているときだけ「変更」を押せる
    private var canRename: Bool {
        guard let editingTag else { return false }
        return !keyword.isEmpty && keyword != editingTag
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
                    .onSubmit {
                        if editingTag != nil {
                            commitRename()
                        } else if canAddKeyword {
                            addKeywordTag()
                        }
                    }
                // 編集中は「追加」の代わりに「変更」を出す
                if editingTag != nil {
                    Button {
                        commitRename()
                    } label: {
                        Label("tag.rename.button", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canRename)
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
                if !searchText.isEmpty || editingTag != nil {
                    Button {
                        // 編集中なら編集をやめる
                        endEditing()
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

            if visibleTags.isEmpty {
                if knownTags.isEmpty && !canAddKeyword {
                    Text("tag.empty")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                SettingFlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(visibleTags, id: \.self) { tag in
                        let isSelected = item.tags.contains(tag)
                        TagChip(title: tag,
                                isSelected: isSelected,
                                isDisabled: !isSelected && isTagLimitReached,
                                isEditing: tag == editingTag,
                                onLongPress: { beginEditing(tag) }) {
                            // 選択を切り替えたら編集はやめる
                            if editingTag != nil {
                                endEditing()
                            }
                            toggle(tag)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
        )
        // 前後のアイテムへ切り替えたときも、そのアイテムで一覧を作り直す
        .task(id: item.id) {
            searchText = ""
            editingTag = nil
            reloadKnownTags()
        }
    }

    private func reloadKnownTags() {
        var tags = pack.tagsByItemCount
        // パック外のアイテム（移動直後など）に付いているタグも出す
        tags.append(contentsOf: item.tags.filter { !tags.contains($0) })
        // このアイテムに付いているタグを先頭にまとめる（それぞれの中はアイテム数の多い順のまま）
        let selected = tags.filter { item.tags.contains($0) }
        let others = tags.filter { !item.tags.contains($0) }
        knownTags = selected + others
    }

    private func toggle(_ tag: String) {
        if let index = item.tags.firstIndex(of: tag) {
            item.tags.remove(at: index)
        } else {
            item.tags = M3Item.sanitizedTags(item.tags + [tag])
        }
    }

    /// 長押ししたタグの名前を検索欄に入れて編集を始める
    private func beginEditing(_ tag: String) {
        editingTag = tag
        searchText = tag
        isSearchFocused = true
    }

    private func endEditing() {
        editingTag = nil
        searchText = ""
    }

    /// 編集中のタグ名を変更する。パック内でそのタグが付いたアイテムすべてに反映する
    /// 変更後の名前が既にあるときは1つのタグにまとまる
    private func commitRename() {
        guard let oldTag = editingTag, canRename else { return }
        let newTag = keyword
        for group in pack.child {
            for target in group.child where target.tags.contains(oldTag) {
                let renamed = target.tags.map { $0 == oldTag ? newTag : $0 }
                target.tags = M3Item.sanitizedTags(renamed)
            }
        }
        // 開いているアイテムがパック外（移動直後など）でも反映する
        if item.tags.contains(oldTag) {
            item.tags = M3Item.sanitizedTags(item.tags.map { $0 == oldTag ? newTag : $0 })
        }
        // 並びはそのままで名前だけ差し替える（既にある名前に変えたときは1つにまとめる）
        if knownTags.contains(newTag) {
            knownTags.removeAll { $0 == oldTag }
        } else {
            knownTags = knownTags.map { $0 == oldTag ? newTag : $0 }
        }
        endEditing()
        isSearchFocused = false
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
