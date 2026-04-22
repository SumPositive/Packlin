//
//  DisplayMode.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI

/// 画面全体の説明量を切り替えるためのモード
enum DisplayMode: String, CaseIterable, Identifiable, Codable {
    // 初期値はConfig.swiftで定義した定数を利用する
    static let `default`: DisplayMode = DEF_displayMode

    case beginner   // 初心者
    case expert     // 達人

    var id: String { rawValue }

    /// UI表示用のローカライズキー
    var localizedKey: LocalizedStringKey {
        switch self {
        case .beginner:
            return "beginner"
        case .expert:
            return "expert"
        }
    }
}

/// アプリ全体の外観を切り替えるためのモード
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    static let `default`: AppearanceMode = .automatic

    case automatic
    case light
    case dark

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .automatic:
            return "auto"
        case .light:
            return "light"
        case .dark:
            return "dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
