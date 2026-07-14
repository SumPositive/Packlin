//
//  ImportAdGateSheet.swift
//  PackList
//
//  公開パックの取込を一定回数ごとにリワード（インタースティシャル）広告視聴で解放するゲート。
//  - 動画を最後まで視聴（報酬獲得）できたら onRewarded を呼ぶ（＝取込＋回数カウントを進める合図）。
//  - 広告在庫が無い等で視聴できないときは、ユーザーを行き止まりにしないため
//    「広告なしで取り込む」導線を出し onSkippedNoAd を呼ぶ（＝取込するが回数は進めない＝次回再挑戦）。
//  - 途中で単に閉じた場合はどちらも呼ばない（取込しない）。
//

import SwiftUI

struct ImportAdGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default

    /// 動画を最後まで視聴して報酬を得たときに呼ばれる（取込＋回数カウントを進める）
    let onRewarded: () -> Void
    /// 広告が見られないため広告なしで取り込むときに呼ばれる（取込するが回数は進めない）
    let onSkippedNoAd: () -> Void

    @StateObject private var loader = RewardedInterstitialAdLoader(adUnitID: ADMOB_REWARD_INTERSTITIAL_UnitID)
    /// 報酬を得たかどうか。得ずに閉じたときに取込しないための判定に使う
    @State private var didEarnReward = false
    /// 広告のロードに失敗したか（在庫無し等）。true のとき広告なし取込を提案する
    @State private var adUnavailable = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "movieclapper")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .padding(.top, 8)

                Text("public.pack.import.ad.title")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("public.pack.import.ad.body")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if adUnavailable == false {
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

                if loader.isLoading {
                    ProgressView(String(localized: "loading.ad"))
                        .padding(.top, 4)
                } else if adUnavailable {
                    // 在庫無し等で見られないときは行き止まりにせず、広告なしで取り込めるようにする
                    Text("public.pack.import.ad.unavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        onSkippedNoAd()
                        dismiss()
                    } label: {
                        Text("public.pack.import.ad.continue.without")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(String(localized: "reload")) {
                        adUnavailable = false
                        loader.loadAd()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        presentAd()
                    } label: {
                        Label {
                            Text("public.pack.import.ad.watch")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 8)
                        } icon: {
                            Image(systemName: loader.isReady ? "play.rectangle" : "pause.rectangle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loader.isReady == false)
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .appFontScale(fontScale)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // キャンセル：何もせず閉じる → 取込は行われない
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
            // 取込ゲートは SSV を使わない（クライアント完結）ため userId は渡さない
            loader.onRewardEarned = { _ in
                // 最後まで視聴して報酬獲得。閉じたあとに取込を続行する
                didEarnReward = true
            }
            loader.onAdDismissed = {
                // 動画が閉じられたら、報酬を得ていればこのシートも閉じて取込へ進む
                if didEarnReward {
                    onRewarded()
                    dismiss()
                }
            }
            loader.onAdFailedToLoad = { _ in
                adUnavailable = true
            }
            loader.onAdFailedToPresent = { _ in
                adUnavailable = true
            }
        }
    }

    private func presentAd() {
        guard let top = UIApplication.topMostViewController() else { return }
        loader.present(from: top)
    }
}
