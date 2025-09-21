//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices

/// 設定画面：Popupで表示する
struct SettingView: View {

    @State private var showSafari = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("お知らせ・設定")
                    Spacer()
                }
                .padding(.horizontal, 4)

                Button {
                    showSafari = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                        Text("アプリの紹介・取扱説明")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)

                RevenueAdsShowcaseView()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .frame(width: 320, height: 360)
        .sheet(isPresented: $showSafari) {
            let urlString = String(localized: "info.url")
            if let url = URL(string: urlString) {
                SafariView(url: url)
            } else {
                Text("setting.infoUnavailable")
            }
        }
    }

    /// カスタムSafariシート
    struct SafariView: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> SFSafariViewController {
            SFSafariViewController(url: url)
        }

        func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    }

    /// 収益広告のプレビューを表示するビュー
    struct RevenueAdsShowcaseView: View {
        private let ads = RevenueAd.previewAds

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("setting.revenueAds.title")
                        .font(.headline)
                    Text("setting.revenueAds.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(ads) { ad in
                    RevenueAdCardView(ad: ad)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 個別の収益広告カード
    struct RevenueAdCardView: View {
        let ad: RevenueAd
        @Environment(\.openURL) private var openURL

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: ad.iconName)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(ad.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(ad.title)
                            .font(.headline)
                        Text(ad.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                if let url = ad.url {
                    Button {
                        openURL(url)
                    } label: {
                        Text("setting.revenueAds.openDemo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.15))
            )
        }
    }

    /// 収益広告のメタデータ
    struct RevenueAd: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let description: LocalizedStringKey
        let urlKey: String
        let iconName: String
        let accentColor: Color

        static let previewAds: [RevenueAd] = [
            RevenueAd(
                titleKey: "setting.revenueAds.banner.title",
                descriptionKey: "setting.revenueAds.banner.description",
                urlKey: "ad.revenue.banner.url",
                iconName: "rectangle.split.3x1.fill",
                accentColor: .blue
            ),
            RevenueAd(
                titleKey: "setting.revenueAds.interstitial.title",
                descriptionKey: "setting.revenueAds.interstitial.description",
                urlKey: "ad.revenue.interstitial.url",
                iconName: "square.on.square.dashed",
                accentColor: .purple
            ),
            RevenueAd(
                titleKey: "setting.revenueAds.rewarded.title",
                descriptionKey: "setting.revenueAds.rewarded.description",
                urlKey: "ad.revenue.rewarded.url",
                iconName: "play.rectangle.fill",
                accentColor: .orange
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
            guard !urlString.isEmpty else {
                return nil
            }
            return URL(string: urlString)
        }
    }
}

#Preview {
    SettingView()
}
