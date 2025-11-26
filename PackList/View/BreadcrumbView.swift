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
        HStack(spacing: 6) {
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
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // 1要素分のテキストを最大幅付きで描画し、末尾に自動省略記号を付ける
    @ViewBuilder
    private func breadcrumbText(for name: String) -> some View {
        Text(name)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: maxNameWidth, alignment: .center)
    }

    // パンくずの区切り記号
    private var separator: some View {
        Text("＞")
            .font(.headline)
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
