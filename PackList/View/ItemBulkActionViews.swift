//
//  ItemBulkActionViews.swift
//  PackList
//
//  タグ式のアイテム縦覧で、選んだアイテムをまとめて操作するときのシート
//  - まとめてタグ付け：パック内のタグを選ぶ（無ければ追加）して、選んだアイテムに付ける
//  - 他のパックへコピー：コピー先のパックを選ぶ
//

import SwiftUI
import SwiftData

/// まとめてタグを付ける／外すシート
struct BulkTagSheet: View {
    enum Mode {
        case add     // タグを付ける（無ければ追加できる）
        case remove  // タグを外す（選んだアイテムに付いているタグだけを出す）
    }

    let pack: M1Pack
    /// 対象のアイテム
    let items: [M3Item]
    let mode: Mode
    /// 付ける／外すタグを決めたとき（シートは呼び出し側で閉じる）
    let onApply: ([String]) -> Void

    private var itemCount: Int { items.count }

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    /// 一覧に出すタグ（開いた時点のパックのタグ＋ここで追加したタグ）
    @State private var knownTags: [String] = []
    @State private var selectedTags: Set<String> = []

    private var keyword: String {
        String(searchText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(APP_MAX_TAG_LEN))
    }

    private var visibleTags: [String] {
        guard !keyword.isEmpty else { return knownTags }
        return knownTags.filter { $0.localizedCaseInsensitiveContains(keyword) }
    }

    private var canAddKeyword: Bool {
        mode == .add && !keyword.isEmpty && !knownTags.contains(keyword)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: (mode == .add ? String(localized: "bulk.tag.message") : String(localized: "bulk.untag.message")), itemCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    // タグを探す（無ければ追加）
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        // 外すときは追加できないので「無ければ追加」を付けない
                        TextField(LocalizedStringKey(mode == .add ? "tag.search.placeholder" : "tag.search.only.placeholder"),
                                  text: $searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit(addKeywordTag)
                        if canAddKeyword {
                            Button(action: addKeywordTag) {
                                Label("tag.add.button", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    // シートの背景と同じ色で欄が見えなくなるので、控えめな枠で区切る
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                    if visibleTags.isEmpty {
                        if knownTags.isEmpty {
                            Text("tag.empty")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        AZFlowLayout(spacing: 8, rowSpacing: 8, alignment: .leading, packToFill: true) {
                            ForEach(visibleTags, id: \.self) { tag in
                                TagChip(title: tag, isSelected: selectedTags.contains(tag)) {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cappedAtLargeFontSize()
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(LocalizedStringKey(mode == .add ? "bulk.tag.title" : "bulk.untag.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedStringKey(mode == .add ? "bulk.tag.apply" : "bulk.untag.apply")) {
                        // 一覧の並び順で渡す
                        onApply(knownTags.filter { selectedTags.contains($0) })
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTags.isEmpty)
                }
            }
        }
        .onAppear {
            switch mode {
            case .add:
                knownTags = pack.tagsByItemCount
            case .remove:
                // 選んだアイテムのどれかに付いているタグだけ（並びはパック内のアイテム数の多い順）
                let used = Set(items.flatMap(\.tags))
                knownTags = pack.tagsByItemCount.filter { used.contains($0) }
                    + used.subtracting(pack.tagsByItemCount).sorted()
            }
        }
    }

    /// 入力した文字でタグを作り、選んだ状態にする
    private func addKeywordTag() {
        let tag = keyword
        guard !tag.isEmpty else { return }
        if !knownTags.contains(tag) {
            knownTags.append(tag)
        }
        selectedTags.insert(tag)
        searchText = ""
    }
}

/// コピー先のパックを選ぶシート
struct BulkCopyPackSheet: View {
    /// コピー元のパック（候補から外す）
    let sourcePack: M1Pack
    let itemCount: Int
    let onSelect: (M1Pack) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \M1Pack.order) private var packs: [M1Pack]

    private var candidates: [M1Pack] {
        packs.filter { $0.id != sourcePack.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { pack in
                        Button {
                            onSelect(pack)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "case")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.accentColor)
                                pack.name.placeholderText("new.pack")
                                    .foregroundStyle(pack.name.isEmpty ? .secondary : .primary)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                // コピー先の分類方式も分かるようにする
                                if pack.classifyMode == .tag {
                                    Image(systemName: "tag.fill")
                                        .foregroundStyle(COLOR_TAG)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        // コピー先で全件を受け入れられる場合だけ選べる
                        .disabled(!pack.canAddItems(itemCount) ||
                                  (pack.classifyMode == .group && !pack.canAddRegularGroup))
                    }
                } header: {
                    Text(String(format: String(localized: "bulk.copy.message"), itemCount))
                }
            }
            .navigationTitle(Text("bulk.copy.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
    }
}
