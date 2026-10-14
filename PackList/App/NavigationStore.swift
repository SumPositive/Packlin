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
        return item.name.localizedCaseInsensitiveContains(keyword) ||
            item.memo.localizedCaseInsensitiveContains(keyword) ||
            item.tags.contains { $0.localizedCaseInsensitiveContains(keyword) }
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
