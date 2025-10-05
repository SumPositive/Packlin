//
//  SettingView.swift
//  PackList
//
//  Created by sumpo on 2025/09/19.
//

import SwiftUI
import SafariServices
import SwiftData
import UniformTypeIdentifiers
import Foundation

/// 設定画面：Popupで表示する
struct SettingView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                SettingSection {
                    // 情報
                    InformationView()
                    // 共有
                    ShareView()
                }

                SettingSection {
                    // カスタム設定
                    CustomSetView()
                }

                SettingSection {
                    // 応援・寄付
                    DonationView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .frame(width: 340, height: 540)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Text("setting.title")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct SettingSection<Content: View>: View {
        @Environment(\.colorScheme) private var colorScheme
        private let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.5 : 0.2), lineWidth: 0.5)
            )
            .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        }

        private var backgroundColor: Color {
            if colorScheme == .dark {
                return Color(uiColor: .tertiarySystemBackground)
            } else {
                return Color(uiColor: .systemBackground)
            }
        }

        private var shadowColor: Color {
            colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.12)
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
                Label {
                    Text("setting.info")
                        .font(.body.weight(.medium))
                        .foregroundColor(.accentColor)
                } icon: {
                    Image(systemName: "info.circle")
                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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

    /// 共有
    struct ShareView: View {
        @Environment(\.modelContext) private var modelContext
     
        @State private var isPresentingImporter = false
        @State private var importErrorMessage: String?
        
        var body: some View {
            // 共有 Pack_*.json を読み込む
            Button(action: {
                isPresentingImporter = true
            }) {
                Label {
                    Text("action.json.download")
                        .font(.body.weight(.medium))
                        .foregroundColor(.accentColor)
                } icon: {
                    ZStack {
                        Image(systemName: "case")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                        Image(systemName: "arrow.down")
                            .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                            .padding(.top, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .fileImporter( // ファイル読み込み
                isPresented: $isPresentingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        do {
                            try importPack(from: url)
                        } catch {
                            debugPrint("Failed to import pack: \(error)")
                            importErrorMessage = String(localized: "setting.import.error.message")
                        }
                    case .failure(let error):
                        debugPrint("Failed to import pack: \(error)")
                        importErrorMessage = String(localized: "setting.import.error.message")
                }
            }
            .alert(
                "setting.import.error.title",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
        /// URLよりJSONファイルをPackExportDTO形式で読み取る
        private func importPack(from url: URL) throws {
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let dto = try decoder.decode(PackJsonDTO.self, from: data)
            
            // チェック
            if dto.copyright != PACK_JSON_DTO_COPYRIGHT {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Copyright mismatch."])
            }
            if dto.version != PACK_JSON_DTO_VERSION {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Version mismatch."])
            }
            
            try createPack(from: dto)
        }
        
        /// DTOよりPackを追加する
        private func createPack(from dto: PackJsonDTO) throws {
            let descriptor = FetchDescriptor<M1Pack>()
            let packs = (try? modelContext.fetch(descriptor)) ?? []
            let newOrder = M1Pack.nextPackOrder(packs)
            // Undo grouping BEGIN
            modelContext.undoManager?.groupingBegin()
            defer {
                // Undo grouping END
                modelContext.undoManager?.groupingEnd()
            }
            // PackJsonDTO をDBへインポートする
            PackImporter.insertPack(from: dto, into: modelContext, order: newOrder)
        }
    }
    
    /// カスタム設定
    struct CustomSetView: View {
        @Environment(\.modelContext) private var modelContext

        @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
        @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = false
        @AppStorage(AppStorageKey.checkOnSufficient) private var checkOnSufficient: Bool = false
        @AppStorage(AppStorageKey.checkOffInsufficient) private var checkOffInsufficient: Bool = false

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                // 新規追加の位置
                HStack(spacing: 8) {
                    Label {
                        Text("setting.insertion.title")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                            .symbolRenderingMode(.hierarchical)
                    }

                    Picker("setting.insertion.title", selection: $insertionPosition) {
                        ForEach(InsertionPosition.allCases) { position in
                            Text(position.localizedKey)
                                .tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                // 必要重量を表示する
                Toggle(isOn: $showNeedWeight) {
                    Label {
                        Text("setting.needWeight.title")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // チェックON時に充足（在庫数＝必要数）にする
                Toggle(isOn: $checkOnSufficient) {
                    Label {
                        Text("setting.checkOnSufficient.title")
                            .font(.body)
                    } icon: {
                        Image(systemName: "circle.circle")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // チェックOFF時に不足（在庫数＝0）にする
                Toggle(isOn: $checkOffInsufficient) {
                    Label {
                        Text("setting.checkOffInsufficient.title")
                            .font(.body)
                    } icon: {
                        Image(systemName: "circle")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
    }
    
    /// 応援・寄付
    struct DonationView: View {
        @State private var showAd = false
        @State private var showAdMovie = false
        @State private var showDonate = false

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Label {
                    Text("ad.empowering.developers")
                        .font(.body.weight(.medium))
                } icon: {
                    Image(systemName: "heart")
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 16) {
                    // 広告を見て寄付する（ボタン）
                    Button(action: {
                        withAnimation {
                            // SafariでURLを表示する
                            showAd = true
                        }
                    }) {
                        Text("ad.donate.banner")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .sheet(isPresented: $showAd) {
                        AdMobBannerContainerView()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            withAnimation {
                                // SafariでURLを表示する
                                showAdMovie = true
                            }
                        }) {
                            Text("ad.donate.video")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .sheet(isPresented: $showAdMovie) {
                            AdMobVideoContainerView()
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical)
                            Text("ad.video.sound")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
