//
//  PopupView.swift
//  Calclin, Packlin
//
//  Created by sumpo/azukid on 2025/08/08.
//

import Foundation
import SwiftUI


/// content を anchor の近くに吹き出しでポップアップ表示する
/// - anchor（グローバル座標）が指す部品の下に出し、下に入らなければ上に出す。吹き出しの先は anchor へ向ける
/// - anchor が nil のときは画面中央に、吹き出しの先なしで出す
struct PopupView<Content: View>: View {
    let anchor: CGPoint?        //=nil:中央に配置
    let onDismiss: () -> Void
    let content: Content

    @State private var contentSize: CGSize = .zero
    /// 出てくるときの拡大アニメーション用
    @State private var isAppeared = false

    /// 吹き出しの先（三角）の幅と高さ
    private let tailWidth: CGFloat = 26
    private let tailHeight: CGFloat = 12
    private let cornerRadius: CGFloat = 20
    /// 本体の内側の余白
    private let innerPadding: CGFloat = 8
    /// anchor（指す部品の中心）から吹き出しの先までの距離。数量カプセルの半分の高さ＋すき間
    private let anchorClearance: CGFloat = 20
    /// 画面端からの最小の余白
    private let screenMargin: CGFloat = 16

    init(anchor: CGPoint? = nil,
         onDismiss: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let layout = balloonLayout(in: geo)

            ZStack(alignment: .topLeading) {
                // 背景タップで閉じる
                Color.black.opacity(0.001)
                    // frameとignoresSafeArea(.container, .all)を適用し、ナビゲーションバー上までタップ領域が広がるようにしている
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .all)
                    .onTapGesture {
                        onDismiss()
                    }

                // 本体（吹き出し）
                content
                    .readSize { size in
                        self.contentSize = size
                    }
                    .padding(innerPadding)
                    // 吹き出しの先のぶん、本体の上か下に余白を空ける
                    .padding(.top, layout.tail == .top ? tailHeight : 0)
                    .padding(.bottom, layout.tail == .bottom ? tailHeight : 0)
                    .background(
                        // 淡いクリーム色の地にして、白い入力欄を引き立てる
                        // 影は「広く淡い影」と「近く細い影」を重ね、浮いて見えるようにする
                        BalloonShape(tail: layout.tail, tailX: layout.tailX,
                                     tailWidth: tailWidth, tailHeight: tailHeight,
                                     cornerRadius: cornerRadius)
                            .fill(COLOR_POPUP_BALLOON)
                            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    )
                    .overlay(
                        BalloonShape(tail: layout.tail, tailX: layout.tailX,
                                     tailWidth: tailWidth, tailHeight: tailHeight,
                                     cornerRadius: cornerRadius)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    // 吹き出しの先を起点に、少し小さい状態からふわっと出す
                    .scaleEffect(isAppeared ? 1 : 0.9, anchor: layout.scaleAnchor)
                    .opacity(isAppeared ? 1 : 0)
                    .onAppear {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isAppeared = true
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                let translation = value.translation
                                if abs(translation.width) >= 20 || abs(translation.height) >= 20 {
                                    onDismiss()
                                }
                            }
                    )
                    .position(layout.center)
            }
        }
    }

    /// 吹き出しの置き方
    private struct BalloonLayout {
        let center: CGPoint
        let tail: BalloonShape.Tail
        /// 吹き出しの先の横位置（吹き出しの左端からの距離）
        let tailX: CGFloat
        let width: CGFloat

        /// 拡大アニメーションの起点（吹き出しの先）
        var scaleAnchor: UnitPoint {
            let x = 0 < width ? tailX / width : 0.5
            switch tail {
            case .top: return UnitPoint(x: x, y: 0)
            case .bottom: return UnitPoint(x: x, y: 1)
            case .none: return .center
            }
        }
    }

    private func balloonLayout(in geo: GeometryProxy) -> BalloonLayout {
        let screen = geo.size
        let bodyWidth = contentSize.width + innerPadding * 2
        let bodyHeight = contentSize.height + innerPadding * 2
        let fullHeight = bodyHeight + tailHeight

        // 中央表示（吹き出しの先なし）
        guard let anchor else {
            let center = CGPoint(x: screen.width / 2, y: screen.height / 2)
            return BalloonLayout(center: center, tail: .none, tailX: bodyWidth / 2, width: bodyWidth)
        }

        // anchor はグローバル座標なので、このビューの座標へ直す
        let origin = geo.frame(in: .global).origin
        let target = CGPoint(x: anchor.x - origin.x, y: anchor.y - origin.y)

        // 横位置：指す部品の真上（真下）を中心に、画面からはみ出さないよう寄せる
        let halfWidth = bodyWidth / 2
        let minX = halfWidth + screenMargin
        let maxX = max(minX, screen.width - halfWidth - screenMargin)
        let centerX = min(max(target.x, minX), maxX)

        // 縦位置：下に入れば下（先は上向き）、入らなければ上（先は下向き）
        let belowTop = target.y + anchorClearance
        let tail: BalloonShape.Tail
        let centerY: CGFloat
        if belowTop + fullHeight <= screen.height - screenMargin {
            tail = .top
            centerY = belowTop + fullHeight / 2
        } else {
            tail = .bottom
            let aboveBottom = target.y - anchorClearance
            centerY = max(fullHeight / 2 + screenMargin, aboveBottom - fullHeight / 2)
        }

        // 先の横位置は指す部品に合わせ、角の丸みにかからない範囲に収める
        let left = centerX - halfWidth
        let tailMin = cornerRadius + tailWidth / 2
        let tailMax = max(tailMin, bodyWidth - cornerRadius - tailWidth / 2)
        let tailX = min(max(target.x - left, tailMin), tailMax)

        return BalloonLayout(center: CGPoint(x: centerX, y: centerY), tail: tail, tailX: tailX, width: bodyWidth)
    }
}

/// 角丸の吹き出し（上か下に三角の先が付く）
struct BalloonShape: Shape {
    enum Tail {
        case none
        case top     // 上向きの先（吹き出しが指す部品の下にある）
        case bottom  // 下向きの先（吹き出しが指す部品の上にある）
    }

    var tail: Tail
    /// 先の横位置（左端からの距離）
    var tailX: CGFloat
    var tailWidth: CGFloat
    var tailHeight: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        // 先のぶんを除いた本体の四角
        var body = rect
        switch tail {
        case .top:
            body.origin.y += tailHeight
            body.size.height -= tailHeight
        case .bottom:
            body.size.height -= tailHeight
        case .none:
            break
        }

        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)
        let x = rect.minX + tailX
        let half = tailWidth / 2
        switch tail {
        case .top:
            path = path.union(tailPath(baseY: body.minY + 1, tipY: rect.minY, x: x, half: half))
        case .bottom:
            path = path.union(tailPath(baseY: body.maxY - 1, tipY: rect.maxY, x: x, half: half))
        case .none:
            break
        }
        return path
    }

    /// 先の形。付け根はなだらかに広げ、とがった先は少し丸める
    private func tailPath(baseY: CGFloat, tipY: CGFloat, x: CGFloat, half: CGFloat) -> Path {
        let dir: CGFloat = tipY < baseY ? -1 : 1     // 先の向き（上なら -1）
        let height = abs(tipY - baseY)
        let tipRound: CGFloat = 3                    // 先の丸み
        var p = Path()
        p.move(to: CGPoint(x: x - half, y: baseY))
        // 付け根から先の手前まで、内側にふくらむ曲線で上がる
        p.addQuadCurve(to: CGPoint(x: x - tipRound, y: tipY - dir * tipRound),
                       control: CGPoint(x: x - half * 0.35, y: baseY + dir * height * 0.55))
        // 先を丸める
        p.addQuadCurve(to: CGPoint(x: x + tipRound, y: tipY - dir * tipRound),
                       control: CGPoint(x: x, y: tipY))
        p.addQuadCurve(to: CGPoint(x: x + half, y: baseY),
                       control: CGPoint(x: x + half * 0.35, y: baseY + dir * height * 0.55))
        p.closeSubpath()
        return p
    }
}

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
