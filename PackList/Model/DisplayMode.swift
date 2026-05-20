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

/// アプリ全体の文字サイズ（Dynamic Type）切り替え
/// - `.system` のときはユーザの iOS 設定（アクセシビリティ）に従う
/// - それ以外は固定の `DynamicTypeSize` を全画面に強制する
enum FontScale: String, CaseIterable, Identifiable, Codable {
    static let `default`: FontScale = .system

    case system   // 自動：iOS のシステム設定に従う
    case standard // 標準
    case large    // 大
    case xLarge   // 特大

    var id: String { rawValue }

    /// セグメントピッカー用ローカライズキー
    var localizedKey: LocalizedStringKey {
        switch self {
        case .system:   return "font.auto"
        case .standard: return "font.standard"
        case .large:    return "font.large"
        case .xLarge:   return "font.xLarge"
        }
    }

    /// `true` のときはモディファイアを適用せずシステム設定をそのまま透過する
    var followsSystem: Bool { self == .system }

    /// 固定サイズ指定時に適用する Dynamic Type のサイズ
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .system:   return .large
        case .standard: return .large
        case .large:    return .xxxLarge
        case .xLarge:   return .accessibility2
        }
    }
}

/// 設定の文字サイズに応じて Dynamic Type を切り替える共通モディファイア
/// - `.system` のときは何も適用せずシステム設定（アクセシビリティ）に従う
/// - それ以外は固定の `DynamicTypeSize` を強制する
/// - シートは presenter の environment を完全には継承しないため、各シート内側でも明示適用すること
struct FontScaleModifier: ViewModifier {
    let fontScale: FontScale

    func body(content: Content) -> some View {
        if fontScale.followsSystem {
            content
        } else {
            content.dynamicTypeSize(fontScale.dynamicTypeSize)
        }
    }
}

extension View {
    /// 設定の文字サイズを適用する。シート内側でも明示的に呼ぶこと
    func appFontScale(_ fontScale: FontScale) -> some View {
        modifier(FontScaleModifier(fontScale: fontScale))
    }
}
