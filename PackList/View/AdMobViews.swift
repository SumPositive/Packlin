//  AdMob表示部品
//  リワード広告、バナー広告、広告エラー処理をまとめる
//

import SwiftUI
import UIKit

import GoogleMobileAds  // iOSのみ、MacやVisionには対応せずエラーになる
import FirebaseCrashlytics

// アプリID は、Info.plistにセット：key:GADApplicationIdentifier

// 利用可能な広告がない場合に共通で表示する文言をまとめておく
private let adUnavailableMessage = String(localized: "no.bonus.ads.now.try.again")

/// ATT不使用のため、常に非パーソナライズ広告リクエストを返す (npa=1)
private func npaRequest() -> Request {
    let request = Request()
    let extras = Extras()
    extras.additionalParameters = ["npa": "1"]
    request.register(extras)
    return request
}

// 広告ユニットID
#if DEBUG
// リワード型 テスト用
let ADMOB_REWARD_UnitID   = "ca-app-pub-3940256099942544/1712485313"
// リワード インタースティシャル テスト用（AdMob公式テストID）
let ADMOB_REWARD_INTERSTITIAL_UnitID = "ca-app-pub-3940256099942544/6978759866"
// アダプティブ バナー テスト用
let ADMOB_BANNER_UnitID = "ca-app-pub-3940256099942544/2435281174"
// インタースティシャル（全画面動画）テスト用
//let ADMOB_VIDEO_UnitID  = "ca-app-pub-3940256099942544/4411468910"
#else // RELEASE || TESTFLIGHT
// リワード型
let ADMOB_REWARD_UnitID   = "ca-app-pub-7576639777972199/1661712828" // reward_1 本番サーバ
//let ADMOB_REWARD_UnitID = "ca-app-pub-7576639777972199/2789248541" // reward_dev 検証サーバ
// リワード インタースティシャル 本番用　公開パック取込時に表示＜＜＜コールバックURLを設定しない＞＞＞
let ADMOB_REWARD_INTERSTITIAL_UnitID = "ca-app-pub-7576639777972199/9603581328" // reward_inter_1
// アダプティブ バナー 本番用
let ADMOB_BANNER_UnitID = "ca-app-pub-7576639777972199/3198136958"
// インタースティシャル（全画面動画）本番用
//let ADMOB_VIDEO_UnitID  = "ca-app-pub-7576639777972199/3403625868"
#endif
// AdMob.reward_1 Cloudサーバーサイドの検証 WebHook URL
// 本番サーバ：https://azuki-api.azukid.com/api/admob/ssv
// AdMob.reward_dev Localサーバーサイドの検証 WebHook URL
// 検証サーバ：https://muriel-chestnutty-unprecedentedly.ngrok-free.dev/api/admob/ssv


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
    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_REWARD_UnitID)
    // 視聴後のメッセージを出し分けるための状態。
    @State private var rewardDescription: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    //Text("タップして広告を見て開発者を応援してください")
                    //    .font(.footnote)
                    //    .multilineTextAlignment(.center)
                    //    .foregroundStyle(.secondary)

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

                        // 新しいトライアル送信の説明文
                        Text(rewardTrialDescription)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 24)
                        
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
            // スクロール位置表示は全画面で出さない
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Text("watch.ad.support"))
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
            // デバッグ操作などでKeychainのuserIdが消えていた場合はここで再発行し、以後も使い回す
            let ensuredUserId = creditStore.regenerateUserIdIfNeeded()
            loader.updateUserId(ensuredUserId)
            loader.onAdDismissed = {
                // 次の動画広告を読み込む
                loader.loadAd()
            }
            loader.onRewardEarned = { _ in
                // 視聴完了直後にトライアル送信を開始する
                rewardDescription = String(localized: "thanks.watching.sending.chappy.mini.now")
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
                    Text("video.ad")
                        .font(.headline)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "movieclapper")
                        .symbolRenderingMode(.hierarchical)
                        .colorMultiply(.primary)
                }

                Label {
                    Text("sound.will.play")
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
            Text("close.x.appears.after.watching")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal)

            HStack {
                Spacer()

                if loader.isLoading {
                    ProgressView(String(localized: "loading.ad"))
                        .padding()
                }else{
                    
                    Button {
                        presentAction()
                    } label: {
                        Label {
                            Text("play.ad")
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
                Button(String(localized: "reload")) {
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

        let request = npaRequest()
        RewardedAd.load(with: adUnitID, request: request) { [weak self] ad, error in
            guard let self else { return }
            Task { @MainActor [self] in
                self.isLoading = false
                if let error {
                    // 具体的な障害内容はCrashlyticsへ残しつつ、画面には優しい文言を出す
                    self.errorMessage = adUnavailableMessage
                    // 広告ロード失敗をAnalyticsへ送り、広告導線の失敗率分析に使う
                    logError(error, domain: "rewarded_ad_load", message: "リワード広告ロード失敗")
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReady = false
            self.rewardedAd = nil
            self.onAdDismissed?()
            self.loadAd()
        }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onAdPresented?()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 実際のエラー内容はログに残し、ユーザーには広告非表示の状況だけを示す
            self.errorMessage = adUnavailableMessage
            // プロセスが落ちた場合などは広告オブジェクトを破棄して再読込を試みる
            self.isReady = false
            self.rewardedAd = nil
            // 広告表示失敗をAnalyticsへ送り、実機依存の表示問題を集計する
            logError(error, domain: "rewarded_ad_present", message: "リワード広告表示失敗")
            // 実機のみに現れるエラー内容をCrashlyticsで把握する
            Crashlytics.crashlytics().record(error: error)
            Crashlytics.crashlytics().log("rewarded_ad_present_failed: \(error.localizedDescription)")
            self.onAdFailedToPresent?(error)
            // 表示失敗のままではユーザーが操作できないため、新しい広告を取りにいく
            self.loadAd()
        }
    }
}

/// リワード インタースティシャル広告のローダー。
/// APIは RewardedAdLoader とほぼ同型（型が RewardedInterstitialAd に変わるだけ）。
/// 公開パックの取込ゲートで使う。在庫が無いとき onAdFailedToLoad が呼ばれる点も同じ。
final class RewardedInterstitialAdLoader: NSObject, ObservableObject, FullScreenContentDelegate {
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
    private var rewardedAd: RewardedInterstitialAd?

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init()
        loadAd()
    }

    // ※ SSV を使わないため userId は保持しない（取込ゲートはクライアント完結）。

    func loadAd() {
        isLoading = true
        isReady = false
        errorMessage = nil

        let request = npaRequest()
        RewardedInterstitialAd.load(with: adUnitID, request: request) { [weak self] ad, error in
            guard let self else { return }
            Task { @MainActor [self] in
                self.isLoading = false
                if let error {
                    self.errorMessage = adUnavailableMessage
                    logError(error, domain: "rewarded_interstitial_load", message: "リワードインタースティシャル広告ロード失敗")
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
        // ※ SSV（ServerSideVerificationOptions）は設定しない。
        //   取込ゲートは「視聴できたら取込を通す」クライアント完結の用途で、
        //   サーバ残高（AI利用券）への付与は不要なため。AdMob 側もこの広告ユニットには
        //   SSV コールバック URL を設定しないこと（設定すると利用券が誤加算される恐れ）。
        isReady = false
        errorMessage = nil
        ad.present(from: root) { [weak self] in
            guard let self else { return }
            self.onRewardEarned?(ad.adReward)
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReady = false
            self.rewardedAd = nil
            self.onAdDismissed?()
            self.loadAd()
        }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onAdPresented?()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.errorMessage = adUnavailableMessage
            self.isReady = false
            self.rewardedAd = nil
            logError(error, domain: "rewarded_interstitial_present", message: "リワードインタースティシャル広告表示失敗")
            Crashlytics.crashlytics().record(error: error)
            Crashlytics.crashlytics().log("rewarded_interstitial_present_failed: \(error.localizedDescription)")
            self.onAdFailedToPresent?(error)
            self.loadAd()
        }
    }
}

/// 画面の端に敷く 320×50 のバナー帯。
/// Vitalin（体調メモ）・Nenrin（年輪）と同じく、1画面に1本だけ置く。
/// パック一覧はヘッダー直下（.top）、シート類は下端（.bottom）に使う。
struct HeaderBannerView: View {
    /// 帯を画面のどちら側に敷くか。区切り線を出す辺がこれで決まる
    enum Placement {
        /// 画面上部（区切り線は帯の下端）
        case top
        /// 画面下部（区切り線は帯の上端）
        case bottom
    }

    /// 帯の向き。既定はパック一覧と同じ上部
    var placement: Placement = .top

    /// 縦方向の余裕。.compact は iPhone 横向きのように画面が低い状態を指す
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// 広告取得失敗後のフォアグラウンド復帰を検知する
    @Environment(\.scenePhase) private var scenePhase

    /// 画面が再描画されてもバナーを作り直さないための固定トークン。
    /// 1バナーにつき1リクエストに保ち、無効トラフィックを避ける
    @State private var reloadToken = UUID()

    /// 広告取得失敗後の表示と自動再試行を管理する状態
    @State private var didFailToLoad = false

    var body: some View {
        // fastlane snapshot 撮影時は広告を出さない（App Store スクショに広告を映さない）。
        // safeAreaInset のインセットが確定するよう高さ0の実体を返す
        if SnapshotSupport.isRunningSnapshot {
            Color.clear.frame(height: 0)
        } else {
            heightAwareBody
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, didFailToLoad else { return }
                    // 通信状態が改善した可能性があるため、フォア復帰時にだけ再取得する
                    retryLoadingAd()
                }
        }
    }

    /// 画面の高さが足りないときだけ広告と帯を畳む。
    ///
    /// 判定は向きではなく verticalSizeClass で行う。.compact になるのは
    /// iPhone の横向きのように縦が詰まった状態だけで、iPad は横向きでも
    /// .regular のままなので広告はそのまま出る（Split View や Slide Over も同様）。
    private var isHeightConstrained: Bool {
        verticalSizeClass == .compact
    }

    /// 高さが足りないときは高さ0にして safeAreaInset ごと畳む。
    /// 50pt＋上下余白の帯が、低い画面では一覧を大きく圧迫するため。
    ///
    /// バナー自体は破棄せず畳むだけにする。作り直すと再リクエストが飛び、
    /// 回転を往復するたびに無効トラフィックとみなされ得るため。
    private var heightAwareBody: some View {
        bannerBody
            .frame(height: isHeightConstrained ? 0 : nil)
            .opacity(isHeightConstrained ? 0 : 1)
            .clipped()
            // 畳んでいる間は広告に触れないようにする
            .allowsHitTesting(!isHeightConstrained)
            .accessibilityHidden(isHeightConstrained)
    }

    private var bannerBody: some View {
        ZStack {
            AdMobBannerRepresentable(
                adUnitID: ADMOB_BANNER_UnitID,
                size: CGSize(width: 320, height: 50),
                onReceiveAd: {
                    // 広告を取得できたら再試行表示を消す
                    didFailToLoad = false
                },
                onFailToReceiveAd: { error in
                    // 帯は残したまま再試行できる状態へ切り替える
                    didFailToLoad = true
                    logError(error, domain: "banner_ad_load", message: "ヘッダーバナー広告ロード失敗")
                    Crashlytics.crashlytics().record(error: error)
                },
                reloadToken: reloadToken
            )
            // トークン更新時にバナー本体を作り直して再取得する
            .id(reloadToken)

            if didFailToLoad {
                // 操作を要求せず、次のフォアグラウンド復帰時に自動再試行する
                Text(adUnavailableMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // 広告と再試行表示の領域を一致させる
        .frame(width: 320, height: 50)
        .frame(maxWidth: .infinity)
        // 上下のタップできる要素（ヘッダーのボタン・パック行）との間を空ける。
        // 誤タップを防ぐだけでなく、広告がアプリの操作面と地続きに
        // 見えないようにするためにも要る
        // （Vitalinで間隔が狭く誤タップを招くとして配信停止された経緯を踏まえた対応）
        .padding(.vertical, 20)
        // 広告の載る面だけ地を一段沈め、アプリのUIではないと分かるようにする。
        // 角丸や左右余白を付けるとアプリのカードに見えてしまうため、
        // 画面端まで届く帯にし、コンテンツ側の区切り線だけで面を分ける
        .background(AdBandNoiseBackground())
        .overlay(alignment: dividerAlignment) {
            // 広告帯とコンテンツの境に引く区切り線。面の境界だけを示す細さに留める
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 0.5)
        }
    }

    /// 区切り線を引く辺。コンテンツと接する側にだけ線を出す
    private var dividerAlignment: Alignment {
        switch placement {
        case .top:
            return .bottom
        case .bottom:
            return .top
        }
    }

    /// バナー本体を作り直して広告取得を再試行する
    private func retryLoadingAd() {
        didFailToLoad = false
        reloadToken = UUID()
    }

}

/// 広告帯の地。砂嵐（ホワイトノイズ）風の粒を敷き、
/// アプリのなめらかな面と質感で区別できるようにする。
///
/// 粒はアプリ起動後に一度だけ UIImage へ焼き、以後はその1枚を敷き詰めるだけ。
/// 毎フレーム粒を描き直すと広告の隣で CPU を使い続けるため、絵は静止させる。
private struct AdBandNoiseBackground: View {
    var body: some View {
        Color(uiColor: .tertiarySystemFill)
            .overlay {
                Image(uiImage: AdBandNoiseImage.shared)
                    .resizable(resizingMode: .tile)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .clipped()
    }
}

/// 砂嵐の粒を焼き付けた繰り返しタイル画像。
/// 生成は初回アクセス時の一度きりで、以後は全画面で同じ1枚を使い回す
private enum AdBandNoiseImage {
    /// タイル1辺の長さ。大きすぎると画像が重くなり、小さすぎると繰り返しに気付かれる
    static let tileSize: CGFloat = 96

    /// 粒の密度。側辺の2乗をこの値で割った数だけ粒を置く。
    /// 小さくするほど粒が詰まって、きめの細かい砂目になる
    static let density: CGFloat = 4

    /// 粒1つの大きさの範囲（pt）。
    /// 1pt前後に抑えると、粒の粗さではなく面の質感として見える
    static let dotSizeRange: ClosedRange<CGFloat> = 0.5...1.0

    /// 粒の濃さの範囲。これを上げると砂目がはっきりし、下げると地に溶ける
    static let dotAlphaRange: ClosedRange<CGFloat> = 0.06...0.13

    static let shared: UIImage = makeTile()

    private static func makeTile() -> UIImage {
        let side = tileSize
        let format = UIGraphicsImageRendererFormat.preferred()
        // 粒は1pt前後の点なので、等倍で焼けば十分（画像サイズも小さく保てる）
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            // 描き直しても同じ模様になるよう、固定の種から粒を置く
            var rng = NoiseGenerator(seed: 0xA5A5_1234)
            let count = Int(side * side / density)
            for _ in 0..<max(count, 0) {
                let x = rng.cgFloat(in: 0...side)
                let y = rng.cgFloat(in: 0...side)
                let dotSide = rng.cgFloat(in: dotSizeRange)
                // 明暗どちらの粒も置いて、ざらつきを均等に見せる
                let isBright = rng.next() % 2 == 0
                let base: UIColor = isBright ? .white : .black
                // 粒の濃さはこの値だけで決める（重ねて薄める処理は入れない）。
                // これより薄いと実寸では地の色と溶けて砂目に見えない
                cg.setFillColor(base.withAlphaComponent(rng.cgFloat(in: dotAlphaRange)).cgColor)
                cg.fill(CGRect(x: x, y: y, width: dotSide, height: dotSide))
            }
        }
        // ダークモードでも同じ粒を使う（明暗両方の粒を含むため反転の必要がない）
        return image.withRenderingMode(.alwaysOriginal)
    }
}

/// 砂嵐の粒を毎回同じ配置にするための擬似乱数（SplitMix64）
private struct NoiseGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &self)
    }
}

/// SwiftUIでAdMobバナーを表示するビュー
struct AdMobBannerView: View {
    let adUnitID: String
    let size: CGSize

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reloadToken = UUID()
    // 一度でも広告を受信したか。List のセル再利用で onAppear が再発火しても
    // ローディング表示に戻さないために使う
    @State private var hasLoaded = false

    var body: some View {
        AdMobBannerRepresentable(
            adUnitID: adUnitID,
            size: size,
            onReceiveAd: {
                // 成功時はエラーメッセージを消しておく
                isLoading = false
                errorMessage = nil
                hasLoaded = true
            },
            onFailToReceiveAd: { error in
                // 配信できなかった場合は優しいメッセージのみ見せ、詳細はCrashlyticsに残す
                isLoading = false
                errorMessage = adUnavailableMessage
                // バナー広告失敗をAnalyticsへ送り、広告枠ごとの問題分析に使う
                logError(error, domain: "banner_ad_load", message: "バナー広告ロード失敗")
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
        // ローディング・エラー表示は行を増やさず、バナー領域への overlay にして高さを一定に保つ
        .overlay {
            if isLoading {
                ProgressView(String(localized: "loading.ad"))
                    .font(.caption)
            // エラー内容がある場合はユーザーに伝えてリトライ手段を用意する（領域全体がリロードボタン）
            } else if errorMessage != nil {
                Button {
                    // バナーを作り直して再リクエストする
                    reloadToken = UUID()
                    isLoading = true
                    // アラート文言をクリアして再試行する
                    errorMessage = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text(adUnavailableMessage)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            // 既に受信済みなら、List のセル再表示で「読み込み中」へ戻さない
            // （戻すと、ロード済みバナーの下にローディング表示が残ってしまう）
            guard hasLoaded == false else { return }
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
        bannerView.load(npaRequest())

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
