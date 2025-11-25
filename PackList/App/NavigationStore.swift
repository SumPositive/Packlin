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

    /// 直近の画面を差し替えて、不要なスタック増加を防ぐ
    func replaceLast(with destination: AppDestination) {
        if !path.isEmpty {
            path.removeLast()
        }
        path.append(destination)
    }
}
