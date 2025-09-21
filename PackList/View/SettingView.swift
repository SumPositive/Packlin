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
    @State private var showAdMovie = false
    @State private var showDonate = false

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
                    Text("広告を見て寄付")
                }
                .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                .sheet(isPresented: $showAd) {
                    AdBannerContainerView()
                }
                Spacer()
            }
            .padding(8)

            HStack {
                // 動画広告を見て寄付する（ボタン）
                Button(action: {
                    withAnimation {
                        // SafariでURLを表示する
                        showAdMovie = true
                    }
                }) {
                    Image(systemName: "heart.fill")
                    Text("動画広告を見て寄付")
                }
                .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                .sheet(isPresented: $showAdMovie) {
                    VideoAdContainerView()
                }
                HStack(spacing: 0) {
                    Image(systemName: "exclamationmark.triangle")
                        .imageScale(.small)
                    Text("音が出ます").font(.caption)
                }
                Spacer()
            }
            .padding(8)
//            Text("無料WiFiに繋いでいる時にでもよろしくお願いします")
//                .font(.caption2)
//                .padding(.leading, 20)
//                .padding(.top, 2)
            
            HStack {
                // **＊送金て寄付する（ボタン）
                Button(action: {
                    withAnimation {
                        // SafariでURLを表示する
                        showDonate = true
                    }
                }) {
                    Image(systemName: "heart.fill")
                    Text("ことら送金で寄付")
                }
                .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                .sheet(isPresented: $showDonate) {
                    //TODO:ことら送金で寄付する
                }
//                HStack(spacing: 0) {
//                    Image(systemName: "exclamationmark.triangle")
//                        .imageScale(.small)
//                    Text("音が出ます").font(.caption)
//                }
                Spacer()
            }
            .padding(8)

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

    /// 静的広告バナーを一覧表示するビュー
    struct AdBannerContainerView: View {
        @Environment(\.dismiss) private var dismiss

        private let banners = AdBanner.supportBanners

        var body: some View {
            NavigationView {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(banners) { banner in
                            AdBannerCardView(banner: banner)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 24)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(Text("setting.adBannerTitle"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "setting.adClose")) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    /// 個別の広告バナーを表示するカード
    struct AdBannerCardView: View {
        let banner: AdBanner
        @Environment(\.openURL) private var openURL

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: banner.iconName)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(banner.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(banner.title)
                            .font(.headline)
                        Text(banner.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Button {
                    if let url = banner.url {
                        openURL(url)
                    }
                } label: {
                    Text("setting.adBannerAction")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(banner.url == nil)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        }
    }

    /// 広告バナー情報
    struct AdBanner: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let description: LocalizedStringKey
        let urlKey: String
        let iconName: String
        let accentColor: Color

        static let supportBanners: [AdBanner] = [
            AdBanner(
                titleKey: "setting.adBanner1.title",
                descriptionKey: "setting.adBanner1.description",
                urlKey: "ad.banner1.url",
                iconName: "hands.sparkles.fill",
                accentColor: .pink
            ),
            AdBanner(
                titleKey: "setting.adBanner2.title",
                descriptionKey: "setting.adBanner2.description",
                urlKey: "ad.banner2.url",
                iconName: "leaf.fill",
                accentColor: .green
            ),
            AdBanner(
                titleKey: "setting.adBanner3.title",
                descriptionKey: "setting.adBanner3.description",
                urlKey: "ad.banner3.url",
                iconName: "book.fill",
                accentColor: .blue
            )
        ]

        init(titleKey: String, descriptionKey: String, urlKey: String, iconName: String, accentColor: Color) {
            self.title = LocalizedStringKey(titleKey)
            self.description = LocalizedStringKey(descriptionKey)
            self.urlKey = urlKey
            self.iconName = iconName
            self.accentColor = accentColor
        }

        var url: URL? {
            let urlString = Bundle.main.localizedString(forKey: urlKey, value: nil, table: nil)
            guard !urlString.isEmpty else { return nil }
            return URL(string: urlString)
        }
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
