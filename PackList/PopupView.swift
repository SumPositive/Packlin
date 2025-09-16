//
//  PopupView.swift
//  Calc26
//
//  Created by sumpo/azukid on 2025/08/08.
//

import Foundation
import SwiftUI


// 画面中央ポップアップ
struct PopupView<Content: View>: View {
    let onDismiss: () -> Void
    let content: Content
    
    @State private var contentSize: CGSize = .zero
    @State private var screenSize: CGSize = .zero
    
    init(onDismiss: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.onDismiss = onDismiss
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geo in
            let screen = geo.size
            
            ZStack(alignment: .topLeading) {
                // 背景タップで閉じる
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }
                
                // 本体
                VStack(spacing: 0) {
                    content
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: SizePreferenceKey.self, value: geo.size)
                            }
                        )
                        .padding(4) // Popupの外枠として見える
                        .background(
                            RoundedRectangle(cornerRadius: 12)
        //                        .fill(COLOR_BACK_SETTING)
                                .shadow(radius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3))
                        )
                }
                .position(popupPosition(screen: screen))
            }
            .onPreferenceChange(SizePreferenceKey.self) {
                // 子ViewのcontentSizeが取得できる
                self.contentSize = $0
            }
            .onAppear { self.screenSize = screen }
        }
    }
    
    /// 表示位置（常に画面の中央）
    func popupPosition(screen: CGSize) -> CGPoint {
        let padding: CGFloat = 8
        let fullWidth = contentSize.width + padding*2  // padding + background
        let fullHeight = contentSize.height + padding*2 // padding
        // 左上座標
        let x = (screen.width - fullWidth) / 2
        let y = (screen.height - fullHeight) / 2
        // 中心座標を返す
        return CGPoint(x: x + fullWidth/2,
                       y: y + fullHeight/2)
    }
}


// --- コンテンツサイズ取得用 PreferenceKey ---
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

//// 吹き出しアライメント指定
//enum ArrowAlignment {
//    case leading
//    case center
//    case trailing
//}
// --- 吹き出し（三角） ---
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}


