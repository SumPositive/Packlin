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
    let anchor: CGPoint?
    let onDismiss: () -> Void
    let content: Content

    @State private var contentSize: CGSize = .zero

    init(anchor: CGPoint? = nil,
         onDismiss: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        self.onDismiss = onDismiss
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geo in
            let screen = geo.size

            ZStack(alignment: .topLeading) {
                // 背景タップで閉じる
                Color.black.opacity(0.001)
                    // frameとignoresSafeArea(.container, .all)を適用し、ナビゲーションバー上までタップ領域が広がるようにしている
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .all)
                    .onTapGesture {
                        onDismiss()
                    }

                // 本体
                VStack(spacing: 0) {
                    content
                        .readSize { size in
                            self.contentSize = size
                        }
                        .padding(4) // Popupの外枠として見える
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(COLOR_POPUP_BORDER)
                                .shadow(radius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3))
                        )
                }
                .position(popupPosition(screen: screen))
            }
        }
        //.ignoresSafeArea(.keyboard, edges: .bottom) // キーボード表示時に位置が変わらないようにする
    }
    
    /// 表示位置（キーボードに隠れないように画面の中央より上に表示する）
    private func popupPosition(screen: CGSize) -> CGPoint {
        let padding: CGFloat = 8
        let fullWidth = contentSize.width + padding * 2  // padding + background
        let fullHeight = contentSize.height + padding * 2 // padding

        if let anchor {
            let halfWidth = fullWidth / 2
            let halfHeight = fullHeight / 2

            let minX = halfWidth
            let maxX = max(halfWidth, screen.width - halfWidth)
            let minY = halfHeight
            let maxY = max(halfHeight, screen.height - halfHeight)

            let clampedX = min(max(anchor.x, minX), maxX)
            let clampedY = min(max(anchor.y, minY), maxY)
            return CGPoint(x: clampedX, y: clampedY)
        }

        // 左上座標
        let x = (screen.width - fullWidth) / 2
        // 中心座標を返す（従来どおりやや上寄せ）
        return CGPoint(x: x + fullWidth / 2,
                       y: max(0, screen.height / 2 - fullHeight))
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


