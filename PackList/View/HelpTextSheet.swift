//
//  HelpTextSheet.swift
//  PackList
//
//  Calclin の (?) ヘルプシートを移植したもの。
//  項目名の右の (?) から、説明文だけのシートを中身の高さぴったりで開く。
//

import SwiftUI

/// 説明文だけのヘルプシート
/// - タイトルは置かず、左上の閉じるボタン（下向き）と説明だけを見せる（下へスワイプでも閉じる）
/// - 背面が透けないよう不透過にし、中身の高さぴったりで開く
struct HelpTextSheet: View {
    /// 説明文（1文1段落、空行区切り）
    let text: LocalizedStringKey
    /// 説明の下に置く下線付きリンク（「設定アプリで変更できます」など）
    var link: AttributedString? = nil
    /// 中身の高さを親へ返す（シートを中身ぴったりの高さで開くため）
    var onMeasured: (CGFloat) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    /// 測っていない部分の高さ（シート上端のつまみまわりの余白）
    private let chromeHeight: CGFloat = 24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 閉じる（ほかのシートと同じ左上の下向きの山型）
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .imageScale(.large)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                // 44pt のタップ範囲のうち上の余白ぶんを詰め、説明との間を空けすぎない
                .padding(.vertical, -8)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Text(link)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            // ScrollView の中身を測る（外枠を測ると開いている高さが返ってしまう）
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard 0 < height else { return }
                onMeasured(height + chromeHeight)
            }
        }
    }
}

/// HelpTextSheet を中身の高さで開く
private struct HelpTextSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let text: LocalizedStringKey
    let link: AttributedString?
    let fontScale: FontScale
    /// 中身の高さ（実測）
    @State private var contentHeight: CGFloat = 0

    /// シートを開く高さ。中身が分かるまでは半画面ぶんで待つ
    private var sheetHeight: CGFloat {
        let screen = UIScreen.main.bounds.height
        guard 0 < contentHeight else { return screen * 0.5 }
        return min(contentHeight, screen * 0.9)
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            HelpTextSheet(text: text, link: link) { height in
                contentHeight = height
            }
            // シートは親の文字サイズを引き継がないので明示適用する
            .appFontScale(fontScale)
            // 中身の高さぴったりで開く（足りなければ引き上げられる）
            .presentationDetents([.height(sheetHeight), .large])
            // 背面が透けないよう不透過にする
            .presentationBackground(Color(.systemBackground))
        }
    }
}

extension View {
    /// 説明文だけのヘルプシートを出す
    func helpTextSheet(isPresented: Binding<Bool>,
                       text: LocalizedStringKey,
                       link: AttributedString? = nil,
                       fontScale: FontScale) -> some View {
        modifier(HelpTextSheetModifier(isPresented: isPresented, text: text,
                                       link: link, fontScale: fontScale))
    }
}

/// 項目名の右に置く (?) ボタン。押すとヘルプシートを開く
struct HelpQuestionButton: View {
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

extension AttributedString {
    /// リンク部分に下線を付ける（訳文の [..](app-settings:) を下線付きリンクとして見せる）
    func underliningLinks() -> AttributedString {
        var text = self
        for run in text.runs where run.link != nil {
            text[run.range].underlineStyle = .single
        }
        return text
    }
}
