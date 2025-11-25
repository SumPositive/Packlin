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



/// バナー広告の表示を管理するビュー
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
    @EnvironmentObject private var adBenefitStore: AdRewardBenefitStore
    // Google AdMob: gsuite@art.jp  　広告ユニット名：PackList V3 Reward
    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_VIDEO_UnitID)
    @State private var rewardDescription: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
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
                #if DEBUG
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // デバッグ時に報酬コールバックが届かないケースを手動再現する
                        loader.simulateRewardEarnedForDebug()
                    } label: {
                        Image(systemName: "sparkles")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(Text(String(localized: "デバッグ用報酬付与")))
                }
                #endif
            }
        }
        .onAppear {
            loader.onAdDismissed = {
                dismiss()
            }
            loader.onRewardEarned = { _ in
                handleRewardEarned()
            }
        }
    }

    private func presentAd() {
        guard let topController = UIApplication.topMostViewController() else {
            return
        }
        loader.present(from: topController)
    }

    private func handleRewardEarned() {
        var messages: [String] = [String(localized: "広告をご視聴いただきありがとうございます！")]
        // すでに無料特典を1回分持っている場合は、使い切ってもらうために新規付与を見送る
        if adBenefitStore.hasBonus {
            messages.append(String(localized: "無料特典は1回分までです。使い切ってから次の特典を受け取れます。"))
            rewardDescription = messages.joined(separator: "\n")
            return
        }
        if registerBonusIfNeeded() {
            messages.append(String(localized: "広告収益が目標を超えたのでAIを1回無料で使えます"))
        }
        rewardDescription = messages.joined(separator: "\n")
    }

    private func registerBonusIfNeeded() -> Bool {
        // paidEventHandlerで受け取った最新の収益情報を使って判定する
        guard let currencyCode = loader.lastPaidCurrencyCode,
              let micros = loader.lastPaidMicros else {
            return false
        }
        if micros < 1 {
            return false
        }
        // AdMobからはマイクロ単位（100万分の1通貨）が渡されるため、大きい単位へ直す
        let majorValue = Double(micros) / 1_000_000
        let upperCurrency = currencyCode.uppercased()
        if upperCurrency == "JPY" {
            return adBenefitStore.grantBonusIfQualified(revenueYen: majorValue, revenueUsd: nil)
        }
        if upperCurrency == "USD" {
            return adBenefitStore.grantBonusIfQualified(revenueYen: nil, revenueUsd: majorValue)
        }
        return false
    }
}

/// AdMobの報酬型広告を読み込むクラス
final class RewardedAdLoader: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    /// 広告が表示された際に通知される最新の収益額（マイクロ単位）
    @Published private(set) var lastPaidMicros: Int64?
    /// 広告の収益通貨コード（JPY, USDなど）。判定できた場合のみ保持する
    @Published private(set) var lastPaidCurrencyCode: String?

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
                    ad.paidEventHandler = { [weak self] adValue in
                        // 収益情報はメインスレッドで保存し、UIの更新に即座に反映させる
                        DispatchQueue.main.async {
                            guard let self else { return }
                            self.lastPaidMicros = adValue.value.int64Value
                            self.lastPaidCurrencyCode = adValue.currencyCode
                        }
                    }
                    self.isReady = true
                }
            }
        }
    }

    func present(from root: UIViewController) {
        guard let rewardedAd else { return }
        let ad = rewardedAd
        ad.present(from: root) { [weak self] in
            // 報酬付与コールバックは任意のスレッドで呼ばれるため、UI更新に備えてメインスレッドへ戻す
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onRewardEarned?(ad.adReward)
            }
        }
    }

    #if DEBUG
    /// DEBUGビルドでAdMobのテスト広告が利用できない環境でも処理確認できるようにする
    func simulateRewardEarnedForDebug() {
        // 収益情報が無いと無料特典判定が行えないため、十分な額を仮設定してから報酬を流す
        let mockMicros: Int64 = 60_000_000 // 60 JPY 相当の想定値
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastPaidMicros = mockMicros
            self.lastPaidCurrencyCode = "JPY"
            // AdRewardはイニシャライザ引数を受け付けないため、モックはデフォルト初期化で生成する
            let reward = AdReward()
            self.onRewardEarned?(reward)
        }
    }
    #endif

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReady = false
            self.rewardedAd = nil
            self.lastPaidMicros = nil
            self.lastPaidCurrencyCode = nil
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
