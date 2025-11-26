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

#if canImport(GoogleMobileAds)
typealias AdPaidValue = AdValue
#else
/// GoogleMobileAdsが利用できない環境向けの代替型。収益カウント用の最小限の情報だけ保持する
struct AdPaidValue {
    let value: NSDecimalNumber
    let currencyCode: String?
}
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



///// バナー広告の表示を管理するビュー
//struct AdMobBannerContainerView: View {
//    @Environment(\.dismiss) private var dismiss
//
//    private let bannerConfigs = [
//        AdMobBannerConfiguration(
//            adUnitID: ADMOB_BANNER_UnitID, // 広告ユニット名：PackList V3 Banner
//            size: CGSize(width: 320, height: 50)
//        ),
//        AdMobBannerConfiguration(
//            adUnitID: ADMOB_BANNER_UnitID,
//            size: CGSize(width: 320, height: 100)
//        ),
//        AdMobBannerConfiguration(
//            adUnitID: ADMOB_BANNER_UnitID,
//            size: CGSize(width: 300, height: 250)
//        )
//    ]
//
//    var body: some View {
//        NavigationView {
//            ScrollView {
//                VStack(spacing: 16) {
//                    ForEach(bannerConfigs) { config in
//                        AdMobBannerCardView(configuration: config, onPaidEvent: nil)
//                    }
//                }
//                .padding()
//            }
//            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
//            .navigationTitle(Text("タップして広告をご覧ください"))
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .navigationBarLeading) {
//                    Button {
//                        // 閉じる
//                        dismiss()
//                    } label: {
//                        Image(systemName: "chevron.down")
//                            .imageScale(.large)
//                            .symbolRenderingMode(.hierarchical)
//                    }
//                }
//            }
//        }
//    }
//}

///// 単一のAdMobバナー広告カード
//struct AdMobBannerCardView: View {
//    let configuration: AdMobBannerConfiguration
//    var onPaidEvent: ((AdPaidValue) -> Void)?
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//
//            AdMobBannerView(
//                adUnitID: configuration.adUnitID,
//                size: configuration.size,
//                onPaidEvent: onPaidEvent
//            )
//
//        }
////        .padding()
////        .frame(maxWidth: .infinity, alignment: .leading)
////        .background(
////            RoundedRectangle(cornerRadius: 24)
////                .fill(Color(uiColor: .secondarySystemBackground))
////        )
//    }
//}

struct AdMobBannerConfiguration: Identifiable {
    let id = UUID()
    let adUnitID: String
    let size: CGSize
}

/// 購入者向けの広告特典状況を示すバッジ
struct AdRewardBonusBadgeView: View {
    @EnvironmentObject private var adBenefitStore: AdRewardBenefitStore
    /// 購入履歴があるかどうかを親ビューから受け取り、案内文を切り替える
    var hasPurchaseHistory: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(String(localized: "購入者特典"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "ticket.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, options: .repeat(2))
            }

            if hasPurchaseHistory {
                Text(String(localized: "広告収益が基準を超えるとAI利用券を1枚追加します"))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "AI利用券を1枚購入すると特典が解放されます"))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if hasPurchaseHistory, let remaining = adBenefitStore.remainingYenToNextGrant {
                Text(String(format: String(localized: "あと%.1f円の寄付で1枚追加"), remaining))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: 200)
    }
}

/// AI利用券が追加されたことを目に見える形で知らせるトースト
struct AdRewardTicketToastView: View {
    var grantedTickets: Int

    var body: some View {
        let safeTickets = grantedTickets <= 0 ? 1 : grantedTickets
        HStack(spacing: 10) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .repeat(3))
            let template = String(localized: "AI利用券を%d枚受け取りました")
            Text(String(format: template, safeTickets))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            Capsule(style: .continuous)
                .fill(Color.blue.opacity(0.9))
        )
        .shadow(radius: 6)
    }
}

#if canImport(GoogleMobileAds)
/// バナー広告と動画広告を1画面にまとめ、収益計測から特典付与まで完結させるビュー
struct AdMobUnifiedSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var adBenefitStore: AdRewardBenefitStore
    @EnvironmentObject private var creditStore: CreditStore
    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_VIDEO_UnitID)

    @State private var rewardDescription: String?
    @State private var infoMessage: String?
    @State private var hasPurchaseHistory = false
    @State private var showTicketAnimation = false
    @State private var lastGrantedTickets = 0

    private let bannerConfig = AdMobBannerConfiguration(
        adUnitID: ADMOB_BANNER_UnitID,
        size: CGSize(width: 320, height: 100)
    )

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    // 広告特典の説明
                    rewardProgressSection
                    // バナー広告
                    bannerSection
                    // 動画広告
                    videoSection
                }
                .padding()
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
            // 広告終了後にサポート画面が閉じないよう、ここでは画面を閉じずに次の広告読み込みだけを行う
            loader.onAdDismissed = {
                loader.loadAd()
            }
            loader.onRewardEarned = { _ in
                handleRewardEarnedFromVideo()
            }
            Task {
                hasPurchaseHistory = await PurchaseHistoryChecker.hasPurchasedOnce()
            }
        }
        .overlay(alignment: .top) {
            if showTicketAnimation {
                AdRewardTicketToastView(grantedTickets: lastGrantedTickets)
                    .padding(.top, 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// 広告特典の説明
    private var rewardProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text(String(localized: "AI利用券を購入した方への特典として、広告収益が一定額を超えるたびにAI利用券を1枚追加します"))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.bottom, 20)
                Spacer()
            }

            HStack {
                Spacer()
                // 特典バッジ
                AdRewardBonusBadgeView(hasPurchaseHistory: hasPurchaseHistory)
                Spacer()
            }
            Text(String(localized: "購入履歴が確認できる端末で視聴した場合にのみAI利用券が追加されます"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }

    /// バナー広告
    private var bannerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("広告")
                    .font(.headline)
            } icon: {
                Image(systemName: "rectangle.fill.on.rectangle.fill")
                    .symbolRenderingMode(.hierarchical)
            }

            Text("広告をタップして開いてください")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // バナー広告
            //AdMobBannerCardView(configuration: bannerConfig)
            AdMobBannerView(
                adUnitID: bannerConfig.adUnitID,
                size: bannerConfig.size,
                onPaidEvent: {_ in
                }
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }

    /// 動画広告
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("動画広告")
                    .font(.headline)
            } icon: {
                Image(systemName: "play.rectangle.on.rectangle")
                    .symbolRenderingMode(.hierarchical)
            }

            if loader.isLoading {
                ProgressView(String(localized: "動画広告を読み込み中..."))
                    .padding(.vertical, 8)
            }else{
                Text("広告を再生して最後までご覧ください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label {
                    Text("音が出る場合があります")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                        .colorMultiply(.red)
                }
            }

            if let errorMessage = loader.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "再読み込み")) {
                        loader.loadAd()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button {
                presentAd()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .symbolRenderingMode(.hierarchical)
                    Text("広告を再生")
                        .font(.body.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(loader.isReady == false)

            
            if let rewardDescription {
                Text(rewardDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }

    private func presentAd() {
        guard let topController = UIApplication.topMostViewController() else {
            return
        }
        loader.present(from: topController)
    }

//    private func registerRevenue(_ adValue: AdPaidValue) {
//        let granted = adBenefitStore.recordRevenue(micros: adValue.value.int64Value, currencyCode: adValue.currencyCode)
//        var messages: [String] = [String(localized: "広告をご視聴いただきありがとうございます！")]
//        if adBenefitStore.hasBonus {
//            messages.append(String(localized: "特典1回無料は受け取り済みです。使い切ると次のカウントが始まります"))
//        }
//        if granted {
//            messages.append(String(localized: "広告の視聴時間と回数が目標を超えたので特典1回無料を付与しました"))
//        }
//        infoMessage = messages.joined(separator: "\n")
//    }

    private func handleRewardEarnedFromVideo() {
        Task {
            // 直前のpaidEventHandlerで拾った収益情報を使って特典付与を試みる
            guard let currencyCode = loader.lastPaidCurrencyCode,
                  let micros = loader.lastPaidMicros else {
                await MainActor.run {
                    rewardDescription = String(localized: "収益情報を取得できませんでしたが、視聴はカウントされました")
                }
                return
            }

            var messages: [String] = [String(localized: "広告をご視聴いただきありがとうございます！")]
            let purchased = await PurchaseHistoryChecker.hasPurchasedOnce()
            await MainActor.run { hasPurchaseHistory = purchased }
            if purchased == false {
                messages.append(String(localized: "この特典は購入者向けです。まずはAI利用券を1枚購入してからお試しください。"))
                await MainActor.run {
                    rewardDescription = messages.joined(separator: "\n")
                }
                return
            }

            let grantedTickets = await MainActor.run {
                adBenefitStore.recordRevenue(micros: micros, currencyCode: currencyCode, hasPurchaseHistory: purchased)
            }
            if grantedTickets < 1 {
                messages.append(String(localized: "寄付が基準に届くとAI利用券を追加します。引き続き応援ありがとうございます。"))
                await MainActor.run {
                    rewardDescription = messages.joined(separator: "\n")
                }
                return
            }

            let synced = await addCreditsFromAdReward(count: grantedTickets, micros: micros, currencyCode: currencyCode)
            if synced {
                let template = String(localized: "購入者特典としてAI利用券を%d枚追加しました。")
                messages.append(String(format: template, grantedTickets))
            } else {
                messages.append(String(localized: "端末内にAI利用券を追加しましたが、サーバー同期に失敗しました。通信環境を整えてから再度ご確認ください。"))
            }
            await MainActor.run {
                rewardDescription = messages.joined(separator: "\n")
            }
        }
    }

    /// サーバーとKeychainの両方へ広告特典によるAI利用券追加を反映する
    /// - Returns: サーバー反映まで成功した場合はtrue
    private func addCreditsFromAdReward(count: Int, micros: Int64, currencyCode: String) async -> Bool {
        if count < 1 {
            return false
        }
        do {
            let balance = try await AzukiApi.shared.grantAdRewardCredit(
                userId: creditStore.userId,
                grantedTickets: count,
                revenueMicros: micros,
                currencyCode: currencyCode
            )
            await MainActor.run {
                creditStore.overwrite(credits: balance)
                lastGrantedTickets = count
                withAnimation(.spring()) {
                    showTicketAnimation = true
                }
            }
            await scheduleToastHide()
            return true
        } catch {
            // サーバー連携に失敗しても端末上では約束通り追加し、後続の同期で整合させる
            await MainActor.run {
                creditStore.add(credits: count)
                lastGrantedTickets = count
                withAnimation(.spring()) {
                    showTicketAnimation = true
                }
            }
            await scheduleToastHide()
            return false
        }
    }

    /// 一時的なトースト表示を一定時間後に消す
    private func scheduleToastHide() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run {
            withAnimation(.easeInOut) {
                showTicketAnimation = false
            }
        }
    }
}
#else
/// GoogleMobileAdsが利用できない環境向けの簡易ビュー
struct AdMobUnifiedSupportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                Text(String(localized: "setting.bannerAdUnavailable"))
                    .multilineTextAlignment(.center)
                    .font(.headline)
                Button(String(localized: "setting.adClose")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle(Text(String(localized: "ad.unified.title")))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif

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
    @EnvironmentObject private var creditStore: CreditStore
    // Google AdMob: gsuite@art.jp  　広告ユニット名：PackList V3 Reward
    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_VIDEO_UnitID)
    @State private var rewardDescription: String?
    @State private var hasPurchaseHistory = false
    @State private var showTicketAnimation = false
    @State private var lastGrantedTickets = 0

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
            // 動画視聴後もサポート画面に留まれるよう、閉じずに次回の広告を準備する
            loader.onAdDismissed = {
                loader.loadAd()
            }
            loader.onRewardEarned = { _ in
                handleRewardEarned()
            }
            Task {
                hasPurchaseHistory = await PurchaseHistoryChecker.hasPurchasedOnce()
            }
        }
        .overlay(alignment: .top) {
            if showTicketAnimation {
                AdRewardTicketToastView(grantedTickets: lastGrantedTickets)
                    .padding(.top, 12)
                    .transition(.scale.combined(with: .opacity))
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
        Task {
            var messages: [String] = [String(localized: "広告をご視聴いただきありがとうございます！")]
            guard let currencyCode = loader.lastPaidCurrencyCode,
                  let micros = loader.lastPaidMicros else {
                await MainActor.run {
                    rewardDescription = String(localized: "収益情報を取得できませんでしたが、視聴はカウントされました")
                }
                return
            }

            let purchased = await PurchaseHistoryChecker.hasPurchasedOnce()
            await MainActor.run { hasPurchaseHistory = purchased }
            if purchased == false {
                messages.append(String(localized: "この特典は購入者向けです。まずはAI利用券を1枚購入してからお試しください。"))
                await MainActor.run {
                    rewardDescription = messages.joined(separator: "\n")
                }
                return
            }

            let grantedTickets = await MainActor.run {
                adBenefitStore.recordRevenue(micros: micros, currencyCode: currencyCode, hasPurchaseHistory: purchased)
            }
            if grantedTickets < 1 {
                messages.append(String(localized: "寄付が基準に届くとAI利用券を追加します。引き続き応援ありがとうございます。"))
                await MainActor.run {
                    rewardDescription = messages.joined(separator: "\n")
                }
                return
            }

            let synced = await addCreditsFromAdReward(count: grantedTickets, micros: micros, currencyCode: currencyCode)
            if synced {
                let template = String(localized: "購入者特典としてAI利用券を%d枚追加しました。")
                messages.append(String(format: template, grantedTickets))
            } else {
                messages.append(String(localized: "端末内にAI利用券を追加しましたが、サーバー同期に失敗しました。通信環境を整えてから再度ご確認ください。"))
            }
            await MainActor.run {
                rewardDescription = messages.joined(separator: "\n")
            }
        }
    }

    /// サーバーとKeychainの両方へ広告特典によるAI利用券追加を反映する
    /// - Returns: サーバー反映まで成功した場合はtrue
    private func addCreditsFromAdReward(count: Int, micros: Int64, currencyCode: String) async -> Bool {
        if count < 1 {
            return false
        }
        do {
            let balance = try await AzukiApi.shared.grantAdRewardCredit(
                userId: creditStore.userId,
                grantedTickets: count,
                revenueMicros: micros,
                currencyCode: currencyCode
            )
            await MainActor.run {
                creditStore.overwrite(credits: balance)
                lastGrantedTickets = count
                withAnimation(.spring()) {
                    showTicketAnimation = true
                }
            }
            await scheduleToastHide()
            return true
        } catch {
            await MainActor.run {
                creditStore.add(credits: count)
                lastGrantedTickets = count
                withAnimation(.spring()) {
                    showTicketAnimation = true
                }
            }
            await scheduleToastHide()
            return false
        }
    }

    /// 一時的なトースト表示を一定時間後に消す
    private func scheduleToastHide() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run {
            withAnimation(.easeInOut) {
                showTicketAnimation = false
            }
        }
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
        // 収益情報が無いとAI利用券追加の判定が行えないため、十分な額を仮設定してから報酬を流す
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
    var onPaidEvent: ((AdPaidValue) -> Void)?

    var body: some View {
        AdMobBannerRepresentable(adUnitID: adUnitID, size: size, onPaidEvent: onPaidEvent)
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
    var onPaidEvent: ((AdPaidValue) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaidEvent: onPaidEvent)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear

        let bannerView = BannerView(adSize: adSizeFor(cgSize: size))
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        bannerView.delegate = context.coordinator
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.paidEventHandler = { adValue in
            // paidEventHandlerはメインスレッド保証ではないためUI更新しないように返却だけ行う
            context.coordinator.onPaidEvent?(adValue)
        }

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
        let onPaidEvent: ((AdPaidValue) -> Void)?
        weak var bannerView: BannerView?

        init(onPaidEvent: ((AdPaidValue) -> Void)?) {
            self.onPaidEvent = onPaidEvent
        }
    }
}
#else
/// SwiftUIでAdMobが利用できない場合のプレースホルダービュー
struct AdMobBannerView: View {
    let adUnitID: String
    let size: CGSize
    var onPaidEvent: ((AdPaidValue) -> Void)?

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
