import SwiftUI

extension View {
    /// レイアウト後のサイズを取得する
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        overlay(
            GeometryReader { proxy in
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear {
                        DispatchQueue.main.async {
                            onChange(proxy.size)
                        }
                    }
                    .onChange(of: proxy.size) { newSize, oldSize in
                        DispatchQueue.main.async {
                            onChange(newSize)
                        }
                    }
            }
        )
    }
}
