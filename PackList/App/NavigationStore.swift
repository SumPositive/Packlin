//
//  NavigationStore.swift
//  PackList
//
//  Created by sumpo on 2025/10/24.
//

import SwiftUI

/// NavigationStackのパスを共有するシンプルなストア
final class NavigationStore: ObservableObject {
    @Published var path = NavigationPath()
    /// パック一覧へ戻った後に表示するパックID
    @Published var packListScrollTargetID: M1Pack.ID?

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
