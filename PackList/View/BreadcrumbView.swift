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
    let rootAction: (() -> Void)?
    let packAction: (() -> Void)?
    let groupAction: (() -> Void)?
    let itemAction: (() -> Void)?

    // アプリ名はローカライズ文字列から取得し、常にパンくずの先頭に置く
    private var appTitle: String {
        String(localized: "app.title")
    }

    var body: some View {
        HStack(spacing: 2) {
            // 階層が深い項目ほど layoutPriority を高くして
            // 縮める必要があるときは先頭（アプリ名）から優先的に省略する
            crumb(for: appTitle, action: rootAction, priority: 1)
            separator
            crumb(for: packName, action: packAction, priority: 2)

            if let groupName = groupName {
                separator
                crumb(for: groupName, action: groupAction, priority: 3)
            }

            if let itemName = itemName {
                separator
                // アイテム名（または現在画面の名前）を最も優先して残す
                crumb(for: itemName, action: itemAction, priority: 4)
            }
        }
        // 左右余白を最小限にし、画面幅をできるだけ活かす
        .padding(.horizontal, 4)
        // ヘッダーを低く保つため、ボタン行との間だけ最小限空ける
        .padding(.top, 2)
        // 全体を左寄せにして、親子関係が視覚的に並ぶようにする
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 1要素分のテキスト。幅制限は付けず、layoutPriority だけで縮約順を制御する
    @ViewBuilder
    private func breadcrumbText(for name: String) -> some View {
        Text(name)
            // 視認性を保ちつつもヘッダー内の高さを抑えるため footnote を採用
            .font(.footnote)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // タップ可能なパンくず要素を生成する
    // layoutPriority は Button / Text の「外側」に付けないと HStack の領域配分に効かないため、
    // Group でラップしてから最後に適用する
    @ViewBuilder
    private func crumb(
        for name: String,
        action: (() -> Void)?,
        priority: Double
    ) -> some View {
        Group {
            if let action = action {
                Button(action: action) {
                    breadcrumbText(for: name)
                }
                // ヘッダー内ではリンク風の見た目を避け、通常テキストのまま押しやすくする
                .buttonStyle(.plain)
            } else {
                breadcrumbText(for: name)
            }
        }
        // 深い階層ほど縮みにくくする（Group の外側に付与）
        .layoutPriority(priority)
    }

    // パンくずの区切り記号（最優先で残す）
    private var separator: some View {
        Text(">")
            // 文字サイズを合わせ、余白を最小限にして密度を高める
            .font(.footnote)
            .foregroundStyle(.secondary)
            // 左右の余白を同じ幅にそろえて、左右で均等な間隔にする
            .padding(.horizontal, 1)
            // 区切り記号は極力縮めず、消えないように固定する
            .fixedSize(horizontal: true, vertical: false)
            // どんな名前よりも優先して残す
            .layoutPriority(100)
    }
}

#Preview {
    VStack(spacing: 16) {
        BreadcrumbView(packName: "とても長いパック名をテストするためのダミー文字列です", groupName: nil, itemName: nil, rootAction: nil, packAction: nil, groupAction: nil, itemAction: nil)
        BreadcrumbView(packName: "短いパック", groupName: "とても長いグループ名をテスト", itemName: nil, rootAction: nil, packAction: nil, groupAction: nil, itemAction: nil)
        BreadcrumbView(packName: "短いパック", groupName: "短いグループ", itemName: "とても長いアイテム名をテスト", rootAction: nil, packAction: nil, groupAction: nil, itemAction: nil)
    }
    .padding()
}
