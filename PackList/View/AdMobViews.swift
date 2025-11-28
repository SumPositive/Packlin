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
    @EnvironmentObject private var creditStore: CreditStore

    // バナーのサイズバリエーションを配列で保持しておく
    private let bannerConfigs = [
//        AdMobBannerConfiguration(
//            adUnitID: ADMOB_BANNER_UnitID, // 広告ユニット名：PackList V3 Banner
//            size: CGSize(width: 320, height: 50)
//        ),
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
                VStack(spacing: 0) {
                    Text("タップして広告を見て開発者を応援してください")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        // バナー広告
                        ForEach(bannerConfigs) { config in
                            AdMobBannerView(
                                adUnitID: config.adUnitID,
                                size: config.size
                            )
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )
                        }
#if canImport(GoogleMobileAds)
                        // 動画広告
                        AdMobRewardedContentView(
                            loader: loader,
                            rewardDescription: $rewardDescription,
                            presentAction: presentAd
                        )
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(uiColor: .tertiarySystemBackground))
                        )
#else
                        // GoogleMobileAdsが利用できない環境では既存のプレースホルダーを表示
                        LegacyVideoAdContainerView()
                            .padding(.vertical, 8)
#endif
                    }
                    .padding()
                }
                .padding(.vertical, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Text("広告を見て寄付"))
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
            // userIdを広告のSSV customRewardTextにも流用し、ユーザー識別を一本化する
            loader.updateUserId(creditStore.userId)
            loader.onAdDismissed = {
                // 次の動画広告を読み込む
                loader.loadAd()
            }
            loader.onRewardEarned = { _ in
                rewardDescription = String(localized: "ご視聴いただきありがとうございます！")
            }
            loader.onAdLoaded = {
                rewardDescription = nil
            }
            loader.onAdFailedToLoad = { error in
                rewardDescription = error.localizedDescription
            }
            loader.onAdPresented = {
                rewardDescription = nil
            }
            loader.onAdFailedToPresent = { error in
                rewardDescription = error.localizedDescription
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

struct AdMobBannerConfiguration: Identifiable {
    let id = UUID()
    let adUnitID: String
    let size: CGSize
}

#if canImport(GoogleMobileAds)
/// 動画広告
struct AdMobRewardedContentView: View {
    @ObservedObject var loader: RewardedAdLoader
    @Binding var rewardDescription: String?
    let presentAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 66) {
                Label {
                    Text("動画広告")
                        .font(.headline)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "movieclapper")
                        .symbolRenderingMode(.hierarchical)
                        .colorMultiply(.primary)
                }

                Label {
                    Text("音が出ます")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                }
            }

            Text("最後まで視聴すると開発者をサポートできます")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
 
            HStack {
                Spacer()

                if loader.isLoading {
                    ProgressView(String(localized: "広告を読み込み中..."))
                        .padding()
                }else{
                    
                    Button {
                        presentAction()
                    } label: {
                        Label {
                            Text("広告を再生する")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 8)
                        } icon: {
                            Image(systemName: loader.isReady ? "play.rectangle" : "pause.rectangle")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!loader.isReady)
                    
                }
                Spacer()
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

    var onAdLoaded: (() -> Void)?
    var onAdFailedToLoad: ((Error) -> Void)?
    var onAdPresented: (() -> Void)?
    var onAdFailedToPresent: ((Error) -> Void)?
    var onAdDismissed: (() -> Void)?
    var onRewardEarned: ((AdReward) -> Void)?

    private let adUnitID: String
    private var userId: String?
    private var rewardedAd: RewardedAd?

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init()
        loadAd()
    }

    /// AdMobのSSV customRewardTextへ埋め込むユーザー識別子を更新する。userIdで統一し、二重管理を避ける
    /// - Parameter id: Keychainで保持している一意なID
    func updateUserId(_ id: String?) {
        guard let id, id.isEmpty == false else {
            userId = nil
            return
        }
        userId = id
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
                    self.onAdFailedToLoad?(error)
                    self.rewardedAd = nil
                } else if let ad {
                    self.rewardedAd = ad
                    ad.fullScreenContentDelegate = self
                    self.isReady = true
                    self.onAdLoaded?()
                }
            }
        }
    }

    func present(from root: UIViewController) {
        guard let rewardedAd else { return }
        let ad = rewardedAd
        if let userId, userId.isEmpty == false {
            // SSV経由でサーバーへ渡す識別子はuserIdで統一し、課金と広告視聴の紐づけを一本化する
            let options = ServerSideVerificationOptions()
            // customRewardTextはアプリ側で自由に設定できる文字列。ここではKeychainに保持しているuserIdをそのまま送る
            // （AdMobドキュメント上ではcustomData表記だが、SDKではcustomRewardText名称になっている点に注意）
            // ここで常にKeychainのIDを流し込むことで、サーバー側でユーザーを一意に認識しやすくなる
            options.customRewardText = userId
            ad.serverSideVerificationOptions = options
        }
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

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onAdPresented?()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.errorMessage = error.localizedDescription
            self.isReady = false
            self.rewardedAd = nil
            self.onAdFailedToPresent?(error)
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
