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
            if #available(iOS 18.0, *) {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 1.0))) // 回転
            } else {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.hierarchical)
            }

            Text("setting.title")
                .font(.title3.weight(.regular))
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
                return Color(uiColor: .systemGray3)
            } else {
                return Color(uiColor: .systemGray6)
            }
        }

        private var shadowColor: Color {
            colorScheme == .dark ? Color.black.opacity(0.65) : Color.black.opacity(0.12)
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
                // SafariでURLを表示する
                showSafari = true
            }) {
                Label {
                    Text("setting.info")
                        .font(.body.weight(.bold))
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
        @State private var importAlert: ImportAlert?
        
        var body: some View {
            // 共有 Pack_*.pack を読み込む
            Button(action: {
                isPresentingImporter = true
            }) {
                Label {
                    Text("action.pack.download")
                        .font(.body.weight(.bold))
                        .foregroundColor(.accentColor)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                        .symbolRenderingMode(.hierarchical) // 奥行きや立体感のある見た目になる
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .fileImporter( // ファイル読み込み
                isPresented: $isPresentingImporter,
                allowedContentTypes: [PACK_FILE_UTTYPE],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        do {
                            let importedPack = try importPack(from: url)
                            importAlert = .success(packName: importedPack.name)
                        } catch {
                            debugPrint("Failed to import pack: \(error)")
                            importAlert = .failure(message: error.localizedDescription)
                        }
                    case .failure(let error):
                        debugPrint("Failed to import pack: \(error)")
                        importAlert = .failure(message: error.localizedDescription)
                }
            }
            .alert(item: $importAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        /// URLより.packファイルをPackExportDTO形式で読み取る
        private func importPack(from url: URL) throws -> M1Pack {
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let decoder = PackJSONDecoderFactory.decoder()
            let dto = try decoder.decode(PackJsonDTO.self, from: data)

            // チェック
            if dto.productName != PACK_JSON_DTO_PRODUCT_NAME {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Product name mismatch."])
            }
            if dto.copyright != PACK_JSON_DTO_COPYRIGHT {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Copyright mismatch."])
            }
            if dto.version != PACK_JSON_DTO_VERSION {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Version mismatch."])
            }
            
            return try createPack(from: dto)
        }

        /// DTOよりPackを追加する
        private func createPack(from dto: PackJsonDTO) throws -> M1Pack {
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
            return PackImporter.insertPack(from: dto, into: modelContext, order: newOrder)
        }

        private enum ImportAlert: Identifiable {
            case success(packName: String)
            case failure(message: String)

            var id: String {
                switch self {
                case .success(let packName):
                    return "success-\(packName)"
                case .failure:
                    return "failure"
                }
            }

            var title: String {
                switch self {
                case .success:
                    return String(localized: "setting.import.success.title")
                case .failure:
                    return String(localized: "setting.import.error.title")
                }
            }

            var message: String {
                switch self {
                case .success(let packName):
                    let format = String(localized: "setting.import.success.message")
                    return String(format: format, packName)
                case .failure(let message):
                    return message
                }
            }
        }
    }
    
    /// カスタム設定
    struct CustomSetView: View {
        @Environment(\.modelContext) private var modelContext

        @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
        @AppStorage(AppStorageKey.showNeedWeight) private var showNeedWeight: Bool = false
        @AppStorage(AppStorageKey.weightDisplayInKg) private var weightDisplayInKg: Bool = false
        @AppStorage(AppStorageKey.linkCheckWithStock) private var linkCheckWithStock: Bool = false
        @AppStorage(AppStorageKey.footerMessage) private var footerMessage: Bool = true

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                // 新規追加の位置
                HStack(spacing: 8) {
                    Label {
                        Text("setting.insertion.title")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "plus.circle")
                            .symbolRenderingMode(.hierarchical)
                    }

                    Picker("setting.insertion.title", selection: $insertionPosition) {
                        ForEach(InsertionPosition.allCases) { position in
                            Image(systemName: position.iconSFname)
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical)
                                .tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                // 必要重量を表示
                Toggle(isOn: $showNeedWeight) {
                    Label {
                        Text("setting.needWeight.title")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // 重量計をKgで表示
                Toggle(isOn: $weightDisplayInKg) {
                    Label {
                        Text("setting.weightDisplayInKg.title")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // チェックと在庫を連動
                Toggle(isOn: $linkCheckWithStock) {
                    Label {
                        Text("setting.linkCheckWithStock.title")
                            .font(.body)
                    } icon: {
                        ZStack{
                            Image(systemName: "checkmark.circle")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                // フッターの説明文（非表示/表示）
                Toggle(isOn: $footerMessage) {
                    Label {
                        Text("setting.footer.message")
                            .font(.body)
                    } icon: {
                        ZStack{
                            Image(systemName: "platter.filled.bottom.iphone")
                                .symbolRenderingMode(.hierarchical)
                        }
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
                    if #available(iOS 18.0, *) {
                        Image(systemName: "heart.fill")
                            .symbolRenderingMode(.hierarchical)
                            .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.periodic(delay: 0.0)))
                    } else {
                        Image(systemName: "heart.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
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
                    .tint(.secondary)
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
                            VStack(spacing: 2) {
                                Text("ad.donate.video")
                                    .frame(maxWidth: .infinity)

                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .imageScale(.small)
                                        .symbolRenderingMode(.hierarchical)
                                    Text("ad.video.sound")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.secondary)
                        .sheet(isPresented: $showAdMovie) {
                            AdMobVideoContainerView()
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
