//
//  AdMobViews.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
#if canImport(AVKit)
import AVKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// アプリID は、Info.plistにセット：key:GADApplicationIdentifier

// 広告ユニットID
#if DEBUG
// アダプティブ バナー テスト用
let ADMOB_BANNER_UnitID = "ca-app-pub-3940256099942544/2435281174"
// インタースティシャル（全画面動画）テスト用
let ADMOB_VIDEO_UnitID  = "ca-app-pub-3940256099942544/4411468910"
#else
// アダプティブ バナー 本番用
let ADMOB_BANNER_UnitID = "ca-app-pub-7576639777972199/3198136958"
// インタースティシャル（全画面動画）本番用
let ADMOB_VIDEO_UnitID  = "ca-app-pub-7576639777972199/3403625868"
#endif



/// バナー広告と動画広告をまとめて確認できるシートビュー
struct AdMobAdSheetView: View {
    @Environment(\.dismiss) private var dismiss

    // バナーのサイズバリエーションを配列で保持しておく
    private let bannerConfigs = [
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID, // 広告ユニット名：PackList V3 Banner
            size: CGSize(width: 320, height: 50)
        ),
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID,
            size: CGSize(width: 320, height: 100)
        ),
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID,
            size: CGSize(width: 300, height: 250)
        )
    ]

    #if canImport(GoogleMobileAds)
    // 報酬型広告を管理するローダー。シート表示中は使い回す。
    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_VIDEO_UnitID)
    // 視聴後のメッセージを出し分けるための状態。
    @State private var rewardDescription: String?
    #endif

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        // バナー広告をシンプルに縦へ並べる
                        ForEach(bannerConfigs) { config in
                            AdMobBannerCardView(configuration: config)
                        }
                    }
                    .padding()

                    #if canImport(GoogleMobileAds)
                    // 報酬型動画広告の視聴エリア。カード風にまとめる。
                    VStack(alignment: .leading, spacing: 16) {
                        AdMobRewardedContentView(
                            loader: loader,
                            rewardDescription: $rewardDescription,
                            presentAction: presentAd
                        )
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    #else
                    // GoogleMobileAdsが利用できない環境では既存のプレースホルダーを表示
                    LegacyVideoAdContainerView()
                        .padding(.vertical, 8)
                    #endif
                }
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Text("タップして広告をご覧ください"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // 閉じる
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        #if canImport(GoogleMobileAds)
        .onAppear {
            // 動画視聴完了後にシートを閉じる・お礼を出す挙動を設定
            loader.onAdDismissed = {
                dismiss()
            }
            loader.onRewardEarned = { _ in
                rewardDescription = String(localized: "広告をご視聴いただきありがとうございます！")
            }
        }
        #endif
    }

    #if canImport(GoogleMobileAds)
    private func presentAd() {
        // 画面最上位のViewControllerを取得して広告を表示
        guard let topController = UIApplication.topMostViewController() else {
            return
        }
        loader.present(from: topController)
    }
    #endif
}

/// バナー広告の表示を管理するビュー（互換用）
struct AdMobBannerContainerView: View {
    @Environment(\.dismiss) private var dismiss

    private let bannerConfigs = [
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID, // 広告ユニット名：PackList V3 Banner
            size: CGSize(width: 320, height: 50)
        ),
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID,
            size: CGSize(width: 320, height: 100)
        ),
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID,
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
            .navigationTitle(Text("タップして広告をご覧ください"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // 閉じる
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
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

            AdMobBannerView(
                adUnitID: configuration.adUnitID,
                size: configuration.size
            )

        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

struct AdMobBannerConfiguration: Identifiable {
    let id = UUID()
    let adUnitID: String
    let size: CGSize
}

/// 動画広告の表示を管理するビュー
struct AdMobVideoContainerView: View {
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
    // Google AdMob: gsuite@art.jp  　広告ユニット名：PackList V3 Reward
    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_VIDEO_UnitID)
    @State private var rewardDescription: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // シート版と同じUIを再利用する
                AdMobRewardedContentView(
                    loader: loader,
                    rewardDescription: $rewardDescription,
                    presentAction: presentAd
                )

                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(Text("動画広告"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // 閉じる
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .onAppear {
            loader.onRewardEarned = { _ in
                rewardDescription = String(localized: "広告をご視聴いただきありがとうございます！")
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

/// 報酬型広告のUI部品。NavigationView内外で共通利用する。
struct AdMobRewardedContentView: View {
    @ObservedObject var loader: RewardedAdLoader
    @Binding var rewardDescription: String?
    let presentAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // ユーザー向けの注意書き
            Text("動画を最後まで視聴すると開発者をサポートできます")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if loader.isLoading {
                ProgressView(String(localized: "広告を読み込み中..."))
                    .padding()
            }

            if let errorMessage = loader.errorMessage {
                VStack(spacing: 8) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "再読み込み")) {
                        loader.loadAd()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button(String(localized: "広告を再生")) {
                presentAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!loader.isReady)

            if let rewardDescription {
                Text(rewardDescription)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
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
#if canImport(AVKit)
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

                Text("動画を最後まで視聴すると開発者をサポートできます")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(Text("動画広告"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        player.pause()
                        // 閉じる
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
    }
}
#else
/// AVKitが利用できない環境向けの簡易的なプレースホルダー
struct LegacyVideoAdContainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text("setting.adUnavailable")
                .multilineTextAlignment(.center)
                .font(.headline)
            Button(String(localized: "閉じる")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
#endif
#endif

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
