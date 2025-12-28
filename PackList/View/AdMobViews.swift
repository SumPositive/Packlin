//
//  AdMobViews.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import UIKit

import GoogleMobileAds  // iOSのみ、MacやVisionには対応せずエラーになる
import FirebaseCrashlytics

// アプリID は、Info.plistにセット：key:GADApplicationIdentifier

// 利用可能な広告がない場合に共通で表示する文言をまとめておく
private let adUnavailableMessage = String(localized: "現在、特典付きの広告がありません。後ほどお試しください")

// 広告ユニットID
#if DEBUG
// リワード型 テスト用
let ADMOB_REWARD_1_UnitID  = "ca-app-pub-3940256099942544/1712485313"
// アダプティブ バナー テスト用
let ADMOB_BANNER_UnitID = "ca-app-pub-3940256099942544/2435281174"
// インタースティシャル（全画面動画）テスト用
//let ADMOB_VIDEO_UnitID  = "ca-app-pub-3940256099942544/4411468910"
#else // RELEASE || TESTFLIGHT
// リワード型
let ADMOB_REWARD_1_UnitID  = "ca-app-pub-7576639777972199/1661712828"
// アダプティブ バナー 本番用
let ADMOB_BANNER_UnitID = "ca-app-pub-7576639777972199/3198136958"
// インタースティシャル（全画面動画）本番用
//let ADMOB_VIDEO_UnitID  = "ca-app-pub-7576639777972199/3403625868"
#endif



/// バナー広告と動画広告をまとめて確認できるシートビュー
struct AdMobAdSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var creditStore: CreditStore
    /// 広告視聴後にトライアル送信を開始するためのコールバック
    let onRewardEarned: () -> Void
    /// 広告シート内に表示する説明文
    let rewardTrialDescription: String

    // バナーのサイズバリエーションを配列で保持しておく
    private let bannerConfigs = [
//        AdMobBannerConfiguration(
//            adUnitID: ADMOB_BANNER_UnitID,
//            size: CGSize(width: 320, height: 100)
//        ),
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID,
            size: CGSize(width: 300, height: 250)
        )
    ]
    
    // 報酬型広告を管理するローダー。シート表示中は使い回す。
    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_REWARD_1_UnitID)
    // 視聴後のメッセージを出し分けるための状態。
    @State private var rewardDescription: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    Text("タップして広告を見て開発者を応援してください")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    // 新しいトライアル送信の説明文
                    Text(rewardTrialDescription)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .padding(.vertical, 4)

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
        .onAppear {
            // 動画視聴完了後にシートを閉じる・お礼を出す挙動を設定
            // userIdを広告のSSV customRewardTextにも流用し、ユーザー識別を一本化する
            loader.updateUserId(creditStore.userId)
            loader.onAdDismissed = {
                // 次の動画広告を読み込む
                loader.loadAd()
            }
            loader.onRewardEarned = { _ in
                // 視聴完了直後にトライアル送信を開始する
                rewardDescription = String(localized: "広告視聴ありがとう！チャッピー mini で送信を始めます")
                onRewardEarned()
            }
            loader.onAdLoaded = {
                rewardDescription = nil
            }
            loader.onAdFailedToLoad = { _ in
                // ユーザーには原因ではなく「今は見られない」ことだけを伝える
                rewardDescription = adUnavailableMessage
            }
            loader.onAdPresented = {
                rewardDescription = nil
            }
            loader.onAdFailedToPresent = { _ in
                // 事前読み込み後の表示エラーも同様に案内する
                rewardDescription = adUnavailableMessage
            }
        }
    }

    private func presentAd() {
        // 画面最上位のViewControllerを取得して広告を表示
        guard let topController = UIApplication.topMostViewController() else {
            return
        }
        loader.present(from: topController)
    }
}

struct AdMobBannerConfiguration: Identifiable {
    let id = UUID()
    let adUnitID: String
    let size: CGSize
}

/// 動画広告
struct AdMobRewardedContentView: View {
    @ObservedObject var loader: RewardedAdLoader
    @Binding var rewardDescription: String?
    let presentAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
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

            //Text("最後まで視聴して特典をお受け取りください")
            // ローカライズ済みの案内文で、動画完了後に閉じるボタンが出ることを知らせる
            Text("最後まで視聴すると閉じる【×】ボタンが現れます")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
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

            if loader.errorMessage != nil {
                //log(.error, "AdMob rewarded ad loading failed: \(errorMessage)")
                Button(String(localized: "再読み込み")) {
                    loader.loadAd()
                }
                .buttonStyle(.borderedProminent)
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
                    // 具体的な障害内容はCrashlyticsへ残しつつ、画面には優しい文言を出す
                    self.errorMessage = adUnavailableMessage
                    // TestFlightでも原因を追いやすいようCrashlyticsへ記録しておく
                    Crashlytics.crashlytics().record(error: error)
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
            // AdMobのSSVはuserIdentifierを設定しないとuser_idがWebhookに含まれず、/api/admob/ssvでユーザー特定できない
            // customRewardTextだけではuser_idが空のままになるため、公式ドキュメントに従いuserIdentifierへKeychainのIDを流し込む
            let options = ServerSideVerificationOptions()
            options.userIdentifier = userId
            options.customRewardText = userId
            ad.serverSideVerificationOptions = options
        }
        // WebKitプロセスが落ちるとRBSAssertionErrorになることがあるため、開始前に状態を明示的に初期化しておく
        // （デバイス依存の不安定要因を吸収し、Crashlyticsで再現環境を追いやすくする）
        isReady = false
        errorMessage = nil
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
            // 実際のエラー内容はログに残し、ユーザーには広告非表示の状況だけを示す
            self.errorMessage = adUnavailableMessage
            // プロセスが落ちた場合などは広告オブジェクトを破棄して再読込を試みる
            self.isReady = false
            self.rewardedAd = nil
            // 実機のみに現れるエラー内容をCrashlyticsで把握する
            Crashlytics.crashlytics().record(error: error)
            Crashlytics.crashlytics().log("rewarded_ad_present_failed: \(error.localizedDescription)")
            self.onAdFailedToPresent?(error)
            // 表示失敗のままではユーザーが操作できないため、新しい広告を取りにいく
            self.loadAd()
        }
    }
}

/// SwiftUIでAdMobバナーを表示するビュー
struct AdMobBannerView: View {
    let adUnitID: String
    let size: CGSize

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 8) {
            AdMobBannerRepresentable(
                adUnitID: adUnitID,
                size: size,
                onReceiveAd: {
                    // 成功時はエラーメッセージを消しておく
                    isLoading = false
                    errorMessage = nil
                },
                onFailToReceiveAd: { error in
                    // 配信できなかった場合は優しいメッセージのみ見せ、詳細はCrashlyticsに残す
                    isLoading = false
                    errorMessage = adUnavailableMessage
                    // 技術的な詳細はクラッシュログで追う
                    Crashlytics.crashlytics().record(error: error)
                },
                reloadToken: reloadToken
            )
            .id(reloadToken)
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )

            if isLoading {
                ProgressView(String(localized: "広告を読み込み中..."))
                    .font(.caption)
            // エラー内容がある場合はユーザーに伝えてリトライ手段を用意する
            } else if errorMessage != nil {
                VStack(spacing: 6) {
                    Text(adUnavailableMessage)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Button(String(localized: "再読み込み")) {
                        // バナーを作り直して再リクエストする
                        reloadToken = UUID()
                        isLoading = true
                        // アラート文言をクリアして再試行する
                        errorMessage = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            // 画面再表示時は毎回最新状態を取りにいく
            isLoading = true
            errorMessage = nil
        }
    }
}

struct AdMobBannerRepresentable: UIViewControllerRepresentable {
    let adUnitID: String
    let size: CGSize
    let onReceiveAd: () -> Void
    let onFailToReceiveAd: (Error) -> Void
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReceiveAd: onReceiveAd,
            onFailToReceiveAd: onFailToReceiveAd
        )
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

        private let onReceiveAd: () -> Void
        private let onFailToReceiveAd: (Error) -> Void

        init(onReceiveAd: @escaping () -> Void, onFailToReceiveAd: @escaping (Error) -> Void) {
            self.onReceiveAd = onReceiveAd
            self.onFailToReceiveAd = onFailToReceiveAd
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onReceiveAd()
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onFailToReceiveAd(error)
        }
    }
}


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
