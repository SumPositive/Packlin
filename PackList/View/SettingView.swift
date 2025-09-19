//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices


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
                    SafariView(url: URL(string: urlString)!)
                }

            }
        }
        .padding(.horizontal, 8)
        .frame(width: 300, height: 300)
        .onAppear {

        }
        .onDisappear() {

        }
    }
}


#Preview {
    SettingView()
}
