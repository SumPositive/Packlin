import SwiftUI

struct BreadcrumbView: View {
    let packName: String
    let groupName: String?
    let itemName: String?
    // 各階層をタップしたときに戻るためのアクション（不要ならnilで非活性表示）
    let packAction: (() -> Void)?
    let groupAction: (() -> Void)?
    let itemAction: (() -> Void)?

    // パック・グループ・アイテム名それぞれの最大幅を画面の1/4に揃え、長文を詰めて表示する
    private var maxNameWidth: CGFloat {
        UIScreen.main.bounds.width / 4
    }

    var body: some View {
        HStack(spacing: 4) {
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

    // タップ可能なパンくず要素を生成する
    @ViewBuilder
    private func crumb(for name: String, action: (() -> Void)?) -> some View {
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

    // パンくずの区切り記号
    private var separator: some View {
        Text("＞")
            // 文字サイズを合わせ、余白を最小限にして密度を高める
            .font(.caption)
            // 左側の余白をなくし、右側だけ少しスペースを空けて並びを詰める
            .padding(.leading, 0)
            .padding(.trailing, 1)
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
