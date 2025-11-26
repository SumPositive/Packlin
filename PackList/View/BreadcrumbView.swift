import SwiftUI

struct BreadcrumbView: View {
    let packName: String
    let groupName: String?
    let itemName: String?

    // パック・グループ・アイテム名それぞれの最大幅を画面の1/4に揃え、長文を詰めて表示する
    private var maxNameWidth: CGFloat {
        UIScreen.main.bounds.width / 4
    }

    var body: some View {
        HStack(spacing: 2) {
            // 先頭のパック名を左寄せ・省略付きで表示
            breadcrumbText(for: packName)

            if let groupName = groupName {
                separator
                breadcrumbText(for: groupName)
            }

            if let itemName = itemName {
                separator
                breadcrumbText(for: itemName)
            }
        }
        // 全体を左寄せにして、親子関係が視覚的に並ぶようにする
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 1要素分のテキストを最大幅付きで描画し、末尾に自動省略記号を付ける
    @ViewBuilder
    private func breadcrumbText(for name: String) -> some View {
        Text(name)
            // 視認性を保ちつつもヘッダー内の高さを抑えるためcaptionサイズを採用
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            // 左寄せで固定幅に収め、文字数が多い場合は末尾を省略
            .frame(maxWidth: maxNameWidth, alignment: .leading)
    }

    // パンくずの区切り記号
    private var separator: some View {
        Text("＞")
            // 文字サイズを合わせ、左右の余白を絞って密度を高める
            .font(.caption)
            .padding(.horizontal, 2)
    }
}

#Preview {
    VStack(spacing: 16) {
        BreadcrumbView(packName: "とても長いパック名をテストするためのダミー文字列です", groupName: nil, itemName: nil)
        BreadcrumbView(packName: "短いパック", groupName: "とても長いグループ名をテスト", itemName: nil)
        BreadcrumbView(packName: "短いパック", groupName: "短いグループ", itemName: "とても長いアイテム名をテスト")
    }
    .padding()
}
