//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices

/// 設定画面：Popupで表示する
struct SettingView: View {
    
    @State private var showSafari = false
    
    var body: some View {
        VStack {
            HStack {
                // 情報（ボタン）
                Button(action: {
                    withAnimation {
                        // SafariでURLを表示する
                        showSafari = true
                    }
                }) {
                    Image(systemName: "info.circle")
                    //.imageScale(.large)
                        .accentColor(.accentColor)
                }
                .padding() // これがないとタップ有効範囲がImageの最小範囲だけになってしまう
                .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                .sheet(isPresented: $showSafari) {
                    let urlString = String(localized: "info.url")
                    if let url = URL(string: urlString) {
                        SafariView(url: url)
                    } else {
                        Text("setting.infoUnavailable")
                    }
                }
                
                Spacer()
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 300, height: 300)
        .onAppear {

        }
        .onDisappear() {

        }
    }
    
    /// カスタムSafariシート
    struct SafariView: UIViewControllerRepresentable {
        let url: URL
        func makeUIViewController(context: Context) -> SFSafariViewController {
            return SFSafariViewController(url: url)
        }
        func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    }

}


#Preview {
    SettingView()
}
