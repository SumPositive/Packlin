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
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape")
                Text("setting.title")
                Spacer()
            }
            .padding(8)
            
            // アプリの紹介・取扱説明
            InformationView()
                .padding(.vertical, 8)

            // カスタム設定
            CustomSetView()
                .padding(.vertical, 8)

            /// 寄付
            DonationView()
                .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 300, height: 500)
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

    /// アプリの紹介・取扱説明
    struct InformationView: View {
        @State private var showSafari = false
        
        var body: some View {
            Button(action: {
                //withAnimation {
                    // SafariでURLを表示する
                    showSafari = true
                //}
            }) {
                Image(systemName: "info.circle")
                Text("setting.info")
                Spacer()
            }
            .padding(8)
            .sheet(isPresented: $showSafari) {
                let urlString = String(localized: "info.url")
                if let url = URL(string: urlString) {
                    SafariView(url: url)
                } else {
                    Text("setting.infoUnavailable")
                }
            }
            .background(Color(.white).opacity(0.5))
            .cornerRadius(10)
        }
    }

    /// カスタム設定
    struct CustomSetView: View {
        
        var body: some View {
            VStack {
                Button(action: {
                    //TODO: PackExportDTOで保存されたpack.jsonを共有メニューから読み込む
                }) {
                    Image(systemName: "arrow.down.message")
                    Text("action.json.download")
                    Spacer()
                }
                .padding(8)
            }
            .background(Color(.white).opacity(0.5))
            .cornerRadius(10)
        }
    }
    
    /// 寄付
    struct DonationView: View {
        @State private var showAd = false
        @State private var showAdMovie = false
        @State private var showDonate = false

        var body: some View {
            VStack {
                HStack {
                    Image(systemName: "heart")
                    Text("ad.empowering.developers")
                    Spacer()
                }
                .padding(8)
                VStack {
                    HStack {
                        // 広告を見て寄付する（ボタン）
                        Button(action: {
                            withAnimation {
                                // SafariでURLを表示する
                                showAd = true
                            }
                        }) {
                            Text("ad.donate.banner")
                        }
                        .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                        .sheet(isPresented: $showAd) {
                            AdMobBannerContainerView()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    
                    HStack {
                        // 動画広告を見て寄付する（ボタン）
                        Button(action: {
                            withAnimation {
                                // SafariでURLを表示する
                                showAdMovie = true
                            }
                        }) {
                            Text("ad.donate.video")
                        }
                        .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                        .sheet(isPresented: $showAdMovie) {
                            AdMobVideoContainerView()
                        }
                        HStack(spacing: 0) {
                            Image(systemName: "exclamationmark.triangle")
                                .imageScale(.small)
                            Text("ad.video.sound").font(.caption)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .padding(.leading, 26)
            }
            .background(Color(.white).opacity(0.5))
            .cornerRadius(10)
        }
    }

}

#Preview {
    SettingView()
}
