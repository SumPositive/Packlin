//
//  NavigationStore.swift
//  PackList
//
//  Created by sumpo on 2025/10/24.
//

import SwiftUI

/// アイテム縦覧の絞り込み条件（タグ・タグなし・検索語）
struct ItemBrowseFilter: Equatable {
    /// 条件を設定したパック（ほかのパックのアイテム詳細には使わない）
    var packID: M1Pack.ID?
    var tag: String?
    var isUntagged = false
    var keyword = ""

    var isActive: Bool { tag != nil || isUntagged || !keyword.isEmpty }

    /// アイテムが条件に合うか
    func matches(_ item: M3Item) -> Bool {
        if let tag, !item.tags.contains(tag) { return false }
        if isUntagged, !item.tags.isEmpty { return false }
        guard !keyword.isEmpty else { return true }
        return item.name.fuzzyContains(keyword) ||
            item.memo.fuzzyContains(keyword) ||
            item.tags.contains { $0.fuzzyContains(keyword) }
    }
}

/// アイテム縦覧の表示順
/// 縦覧は数量などを変えても行を動かさないので、アイテム詳細の前へ・次へも同じ並びをたどる
struct ItemBrowseOrder {
    /// 並びを記録したパック（ほかのパックのアイテム詳細には使わない）
    var packID: M1Pack.ID?
    var itemIDs: [M3Item.ID] = []

    /// 最新順のアイテムを、縦覧に表示中の並びに合わせる
    /// 縦覧と同じく、削除されたものは除き、新しく増えたものは末尾に付ける
    func arranged(_ items: [M3Item], packID: M1Pack.ID) -> [M3Item] {
        guard self.packID == packID, !itemIDs.isEmpty else { return items }
        let map = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var arranged = itemIDs.compactMap { map[$0] }
        let existingIDs = Set(itemIDs)
        arranged.append(contentsOf: items.filter { !existingIDs.contains($0.id) })
        return arranged
    }
}

/// NavigationStackのパスを共有するシンプルなストア
final class NavigationStore: ObservableObject {
    @Published var path = NavigationPath()
    /// パック一覧へ戻った後に表示するパックID
    @Published var packListScrollTargetID: M1Pack.ID?
    /// アイテム縦覧の絞り込み条件。縦覧から開いたアイテム詳細の前へ・次へを、絞り込みどおりにたどるために使う
    /// （画面の再描画には関わらないので @Published にしない）
    var browseFilter = ItemBrowseFilter()
    /// アイテム縦覧の表示順。縦覧から開いたアイテム詳細の前へ・次へを、一覧の見た目どおりにたどるために使う
    var browseOrder = ItemBrowseOrder()
    /// アイテム詳細でコピーしたアイテムを、縦覧でコピー元の直下に並べるための依頼（コピーしたID → コピー元ID）
    /// 縦覧は表示順を固定しているので、依頼が無いと新しいアイテムは末尾に付く
    var pendingDuplicateSources: [M3Item.ID: M3Item.ID] = [:]

    /// 直近の画面を差し替えて、不要なスタック増加を防ぐ
    func replaceLast(with destination: AppDestination) {
        if !path.isEmpty {
            path.removeLast()
        }
        path.append(destination)
    }

    /// パック一覧へ戻し、指定パックを表示対象にする
    func showPackList(packID: M1Pack.ID) {
        path = NavigationPath()
        packListScrollTargetID = packID
    }
}
