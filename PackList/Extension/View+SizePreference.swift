import SwiftUI

/// 子ビューのサイズを読み取るためのPreferenceKey
private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    /// 表示されるコンテンツのサイズを取得する
    /// - Parameter onChange: サイズ変更時に呼び出されるクロージャ
    /// - Returns: サイズの読み取りを行うビュー
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geo.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}
