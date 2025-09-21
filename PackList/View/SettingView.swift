//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices
import AVKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

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

        private let bannerConfigs = [
            AdMobBannerConfiguration(
                title: "ad.banner1.title",
                message: "ad.banner1.message",
                adUnitID: "ca-app-pub-3940256099942544/2934735716",
                size: CGSize(width: 320, height: 50)
            ),
            AdMobBannerConfiguration(
                title: "ad.banner2.title",
                message: "ad.banner2.message",
                adUnitID: "ca-app-pub-3940256099942544/2934735716",
                size: CGSize(width: 320, height: 100)
            ),
            AdMobBannerConfiguration(
                title: "ad.banner3.title",
                message: "ad.banner3.message",
                adUnitID: "ca-app-pub-3940256099942544/2934735716",
                size: CGSize(width: 300, height: 250)
            )
        ]

        var body: some View {
            NavigationView {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(bannerConfigs) { config in
                            AdMobBannerCardView(configuration: config)
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

    /// 単一のAdMobバナー広告カード
    struct AdMobBannerCardView: View {
        let configuration: AdMobBannerConfiguration

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(configuration.title)
                    .font(.headline)

                AdMobBannerView(
                    adUnitID: configuration.adUnitID,
                    size: configuration.size
                )

                Text(configuration.message)
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

    struct AdMobBannerConfiguration: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let message: LocalizedStringResource
        let adUnitID: String
        let size: CGSize
    }

    /// 動画広告の表示を管理するビュー
    struct VideoAdContainerView: View {
        var body: some View {
            #if canImport(GoogleMobileAds)
            AdMobRewardedScreen()
            #else
            LegacyVideoAdContainerView()
            #endif
        }
    }

#if canImport(GoogleMobileAds)
    /// AdMob報酬型広告の表示ビュー
    struct AdMobRewardedScreen: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var loader = RewardedAdLoader(adUnitID: "ca-app-pub-3940256099942544/1712485313")
        @State private var rewardDescription: String?

        var body: some View {
            NavigationView {
                VStack(spacing: 24) {
                    Text("setting.adDescription")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if loader.isLoading {
                        ProgressView(String(localized: "setting.adLoading"))
                            .padding()
                    }

                    if let errorMessage = loader.errorMessage {
                        VStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button(String(localized: "setting.adRetry")) {
                                loader.loadAd()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Button(String(localized: "setting.adPlay")) {
                        presentAd()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!loader.isReady)

                    if let rewardDescription {
                        Text(rewardDescription)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.top, 24)
                .background(Color(uiColor: .systemBackground))
                .navigationTitle(Text("setting.adVideoTitle"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "setting.adClose")) {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                loader.onAdDismissed = {
                    dismiss()
                }
                loader.onRewardEarned = { _ in
                    rewardDescription = String(localized: "setting.adRewardThanks")
                }
            }
        }

        private func presentAd() {
            guard let topController = UIApplication.topMostViewController() else {
                return
            }
            loader.present(from: topController)
        }
    }

    /// AdMobの報酬型広告を読み込むクラス
    final class RewardedAdLoader: NSObject, ObservableObject, FullScreenContentDelegate {
        @Published private(set) var isLoading = false
        @Published private(set) var isReady = false
        @Published private(set) var errorMessage: String?

        var onAdDismissed: (() -> Void)?
        var onRewardEarned: ((AdReward) -> Void)?

        private let adUnitID: String
        private var rewardedAd: RewardedAd?

        init(adUnitID: String) {
            self.adUnitID = adUnitID
            super.init()
            loadAd()
        }

        func loadAd() {
            isLoading = true
            isReady = false
            errorMessage = nil

            let request = Request()
            RewardedAd.load(with: adUnitID, request: request) { [weak self] ad, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.rewardedAd = nil
                    } else if let ad {
                        self.rewardedAd = ad
                        ad.fullScreenContentDelegate = self
                        self.isReady = true
                    }
                }
            }
        }

        func present(from root: UIViewController) {
            guard let rewardedAd else { return }
            let ad = rewardedAd
            ad.present(from: root) { [weak self] in
                guard let self else { return }
                self.onRewardEarned?(ad.adReward)
            }
        }

        func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReady = false
                self.rewardedAd = nil
                self.onAdDismissed?()
                self.loadAd()
            }
        }

        func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.errorMessage = error.localizedDescription
                self.isReady = false
                self.rewardedAd = nil
            }
        }
    }

    /// SwiftUIでAdMobバナーを表示するビュー
    struct AdMobBannerView: View {
        let adUnitID: String
        let size: CGSize

        var body: some View {
            AdMobBannerRepresentable(adUnitID: adUnitID, size: size)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )
        }
    }

    struct AdMobBannerRepresentable: UIViewControllerRepresentable {
        let adUnitID: String
        let size: CGSize

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIViewController(context: Context) -> UIViewController {
            let viewController = UIViewController()
            viewController.view.backgroundColor = .clear

            let bannerView = BannerView(adSize: adSizeFor(cgSize: size))
            bannerView.adUnitID = adUnitID
            bannerView.rootViewController = viewController
            bannerView.delegate = context.coordinator
            bannerView.translatesAutoresizingMaskIntoConstraints = false

            viewController.view.addSubview(bannerView)
            NSLayoutConstraint.activate([
                bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
                bannerView.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
            ])

            context.coordinator.bannerView = bannerView
            bannerView.load(Request())

            return viewController
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            context.coordinator.bannerView?.rootViewController = uiViewController
        }

        final class Coordinator: NSObject, BannerViewDelegate {
            weak var bannerView: BannerView?
        }
    }
#else
    /// SwiftUIでAdMobが利用できない場合のプレースホルダービュー
    struct AdMobBannerView: View {
        let adUnitID: String
        let size: CGSize

        var body: some View {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .tertiarySystemFill))
                .overlay(
                    Text("setting.bannerAdUnavailable")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(8)
                )
                .frame(height: size.height)
                .frame(maxWidth: .infinity)
        }
    }
#endif

#if !canImport(GoogleMobileAds)
    /// AdMobが利用できない場合の動画広告プレースホルダー
    struct LegacyVideoAdContainerView: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            if let adURL = URL(string: String(localized: "ad.video.url")) {
                LegacyVideoAdView(adURL: adURL)
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

    struct LegacyVideoAdView: View {
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
#endif

}

#if canImport(UIKit)
extension UIApplication {
    static func topMostViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { scene in
            (scene as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        }
        .first) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return topMostViewController(base: navigationController.visibleViewController)
        }
        if let tabController = base as? UITabBarController, let selected = tabController.selectedViewController {
            return topMostViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}
#endif


#Preview {
    SettingView()
}
