//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices
import AVKit

/// 設定画面：Popupで表示する
struct SettingView: View {
    
    @State private var showSafari = false
    @State private var showAd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape")
                Text("お知らせ・設定")
                Spacer()
            }
            .padding(8)
            
            HStack {
                // 情報（ボタン）
                Button(action: {
                    withAnimation {
                        // SafariでURLを表示する
                        showSafari = true
                    }
                }) {
                    Image(systemName: "info.circle")
                    Text("アプリの紹介・取扱説明")
                }
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
            .padding(8)

            HStack {
                // 広告を見て寄付する（ボタン）
                Button(action: {
                    withAnimation {
                        // SafariでURLを表示する
                        showAd = true
                    }
                }) {
                    Image(systemName: "heart.fill")
                    Text("広告を見て寄付する")
                }
                .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                .sheet(isPresented: $showAd) {
                    VideoAdContainerView()
                }
                
                Spacer()
            }
            .padding(8)
//            Text("無料WiFiに繋いでいる時にでもよろしくお願いします")
//                .font(.caption2)
//                .padding(.leading, 20)
//                .padding(.top, 2)
            

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

    /// 広告動画の表示を管理するビュー
    struct VideoAdContainerView: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            if let adURL = URL(string: String(localized: "ad.video.url")) {
                VideoAdView(adURL: adURL)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("setting.adUnavailable")
                        .multilineTextAlignment(.center)
                        .font(.headline)
                    Button(String(localized: "setting.adClose")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }

    /// 動画広告を再生するビュー
    struct VideoAdView: View {
        let adURL: URL
        @Environment(\.dismiss) private var dismiss
        @State private var player: AVPlayer

        init(adURL: URL) {
            self.adURL = adURL
            _player = State(initialValue: AVPlayer(url: adURL))
        }

        var body: some View {
            NavigationView {
                VStack(spacing: 24) {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }

                    Text("setting.adDescription")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 24)
                .background(Color(uiColor: .systemBackground))
                .navigationTitle(Text("setting.adVideoTitle"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "setting.adClose")) {
                            player.pause()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

}


#Preview {
    SettingView()
}
