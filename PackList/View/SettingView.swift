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
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape")
                Text("お知らせ・設定")
                Spacer()
            }
            .padding(8)
            
            InformationView()
                .padding(.vertical, 8)

            DonationView()
                .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 300, height: 340)
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
                Text("アプリの紹介・取扱説明")
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
                    Text("開発者を支援する")
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
                            Text("広告を見て寄付")
                        }
                        .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                        .sheet(isPresented: $showAd) {
                            BannerAdContainerView()
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
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    
                    HStack {
                        // **＊送金て寄付する（ボタン）
                        Button(action: {
                            withAnimation {
                                // SafariでURLを表示する
                                showDonate = true
                            }
                        }) {
                            Text("ことら送金で寄付")
                        }
                        .contentShape(Rectangle()) // paddingを含む領域全体をタップ対象にする
                        .sheet(isPresented: $showDonate) {
                            //TODO:ことら送金で寄付する
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .padding(.leading, 26)
            }
            .background(Color(.white).opacity(0.5))
            .cornerRadius(12)
        }
    }

    /// バナー広告の表示を管理するビュー
    struct BannerAdContainerView: View {
        @Environment(\.dismiss) private var dismiss

        private let banners = BannerAd.sampleBanners

        var body: some View {
            NavigationView {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(banners) { banner in
                            BannerAdCardView(banner: banner)
                        }
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .navigationTitle(Text("setting.bannerAdTitle"))
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

    /// 単一のバナー広告を表示するカード
    struct BannerAdCardView: View {
        let banner: BannerAd

        var body: some View {
            Group {
                if let destination = banner.destination {
                    Link(destination: destination) {
                        cardContent
                    }
                    .buttonStyle(.plain)
                } else {
                    cardContent
                }
            }
        }

        private var cardContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(banner.title)
                    .font(.headline)

                BannerAdImageView(imageURL: banner.imageURL)

                Text(banner.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.05))
            )
        }
    }

    /// バナー広告の画像を読み込んで表示する
    struct BannerAdImageView: View {
        let imageURL: URL?

        var body: some View {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(placeholderBackground)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        private var placeholder: some View {
            ZStack {
                placeholderBackground
                Text("setting.bannerAdUnavailable")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }

        private var placeholderBackground: some View {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .tertiarySystemFill))
        }
    }

    /// バナー広告の定義
    struct BannerAd: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let message: LocalizedStringResource
        let destination: URL?
        let imageURL: URL?

        static let sampleBanners: [BannerAd] = [
            BannerAd(
                title: "ad.banner1.title",
                message: "ad.banner1.message",
                destination: URL(string: "https://www.japan.travel/ja/"),
                imageURL: URL(string: "https://dummyimage.com/600x200/0f9d58/ffffff&text=Travel+Deals")
            ),
            BannerAd(
                title: "ad.banner2.title",
                message: "ad.banner2.message",
                destination: URL(string: "https://www.jtb.co.jp/"),
                imageURL: URL(string: "https://dummyimage.com/600x200/4285f4/ffffff&text=Packing+Checklist")
            ),
            BannerAd(
                title: "ad.banner3.title",
                message: "ad.banner3.message",
                destination: URL(string: "https://hoken.mynavi.jp/"),
                imageURL: URL(string: "https://dummyimage.com/600x200/fbbc05/333333&text=Travel+Insurance")
            )
        ]
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
