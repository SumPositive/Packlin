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

    case beginner
    case expert

    var id: String { rawValue }

    /// UI表示用のローカライズキー
    var localizedKey: LocalizedStringKey {
        switch self {
        case .beginner:
            return "初心者"
        case .expert:
            return "上級者"
        }
    }
}
