//
//  BreadcrumbView.swift
//  Packlin  Pack>Group>Itemをパンくずリスト表示する
//
//  Created by sumpo on 2025/11/27.
//

import SwiftUI
import UIKit

struct BreadcrumbView: View {
    let packName: String
    let groupName: String?
    let itemName: String?
    // 各階層をタップしたときに戻るためのアクション（不要ならnilで非活性表示）
    let packAction: (() -> Void)?
    let groupAction: (() -> Void)?
    let itemAction: (() -> Void)?

    // 各パンくずの最大幅を画面の1/3以内にする
    private var maxNameWidth: CGFloat {
        (UIScreen.main.bounds.width - 36.0*2) / 3.0
    }

    // footnoteフォントでの実測幅を取得し、最大幅を超えないようにする
    private func nameWidth(for name: String) -> CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let attributes = [NSAttributedString.Key.font: font]
        let measuredWidth = (name as NSString).size(withAttributes: attributes).width
        // 実測幅が最大幅より小さければそのまま、長ければ最大幅に抑える
        return min(measuredWidth, maxNameWidth)
    }

    var body: some View {
        HStack(spacing: 2) {
            // 先頭のパック名を左寄せ・省略付きで表示し、タップでパック一覧へ戻れるようにする
            crumb(for: packName, action: packAction)

            if let groupName = groupName {
                separator
                // グループ名もタップで上位画面へ戻れるようにする
                crumb(for: groupName, action: groupAction)
            }

            if let itemName = itemName {
                separator
                // アイテム名（またはソート名）も同様にタップ可にする
                crumb(for: itemName, action: itemAction)
            }
        }
        // 左余白を少し広げて、ヘッダー内での窮屈さを和らげる
        .padding(.leading, 12)
        // 上方向にも十分な空き領域を設け、ヘッダーと重ならないようにする（元より+8pt）
        .padding(.top, 8)
        // 全体を左寄せにして、親子関係が視覚的に並ぶようにする
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 1要素分のテキストを最大幅付きで描画し、末尾に自動省略記号を付ける
    @ViewBuilder
    private func breadcrumbText(for name: String) -> some View {
        Text(name)
            // 視認性を保ちつつもヘッダー内の高さを抑えるためcaptionサイズを採用
            .font(.footnote)
            .lineLimit(1)
            .truncationMode(.tail)
            // 左寄せで幅は文字列ぶんの最小限にしつつ、最大幅を超えないように制限
            .frame(width: nameWidth(for: name), alignment: .leading)
    }

    // タップ可能なパンくず要素を生成する
    @ViewBuilder
    private func crumb(for name: String, action: (() -> Void)?) -> some View {
        if let action = action {
            Button(action: action) {
                breadcrumbText(for: name)
            }
            // ヘッダー内ではリンク風の見た目を避け、通常テキストのまま押しやすくする
            .buttonStyle(.plain)
            //.padding(3)
            //.background(
            //    Capsule(style: .continuous)
            //        .fill(Color.secondary.opacity(0.2))
            //)
        } else {
            breadcrumbText(for: name)
        }
    }

    // パンくずの区切り記号
    private var separator: some View {
        Text("＞")
            // 文字サイズを合わせ、余白を最小限にして密度を高める
            .font(.footnote)
            .foregroundStyle(.secondary)
            // 左右の余白を同じ幅にそろえて、左右で均等な間隔にする
            .padding(.horizontal, 1)
    }
}

#Preview {
    VStack(spacing: 16) {
        BreadcrumbView(packName: "とても長いパック名をテストするためのダミー文字列です", groupName: nil, itemName: nil, packAction: nil, groupAction: nil, itemAction: nil)
        BreadcrumbView(packName: "短いパック", groupName: "とても長いグループ名をテスト", itemName: nil, packAction: nil, groupAction: nil, itemAction: nil)
        BreadcrumbView(packName: "短いパック", groupName: "短いグループ", itemName: "とても長いアイテム名をテスト", packAction: nil, groupAction: nil, itemAction: nil)
    }
    .padding()
}
