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

/// 新規追加する位置
enum InsertionPosition: String, CaseIterable, Identifiable, Codable {
    // 選択肢
    case head // 先頭
    case tail // 末尾
    // 初期値
    static let `default`: InsertionPosition = .head
    
    var id: String { rawValue }
    
    var localizedKey: LocalizedStringKey {
        switch self {
            case .head:
                return "setting.insertion.head"
            case .tail:
                return "setting.insertion.tail"
        }
    }
    
    var iconSFname: String {
        switch self {
            case .head:
                return "text.line.first.and.arrowtriangle.forward"
            case .tail:
                return "text.line.last.and.arrowtriangle.forward"
        }
    }
}

/// 設定画面：以前はPopup表示だったが、PackEditViewと揃えてシート表示に対応
struct SettingView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        SettingSection {
                            // 情報
                            InformationView()
                        }
                        
                        SettingSection {
                            // 保存パックを読み込む
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
                // シートでは端末サイズに追従させるため、幅と高さの固定は行わない
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, -20)
            }
            .navigationTitle(Text("設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
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
                GALogger.log(.function(name: "settings", option: "tap_info"))
            }) {
                Label {
                    Text("アプリの紹介・取扱説明")
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
                    Text("情報を表示できません")
                }
            }
        }
    }

    /// 共有
    struct ShareView: View {
        @Environment(\.modelContext) private var modelContext

        /// 設定画面で指定された挿入位置を共有インポートにも適用するためのAppStorage
        @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
        @State private var isPresentingImporter = false
        @State private var importAlert: ImportAlert?
        
        var body: some View {
            // 共有 Pack_*.pack を読み込む
            Button(action: {
                isPresentingImporter = true
                GALogger.log(.function(name: "settings", option: "tap_import"))
            }) {
                Label {
                    Text("パックを読み込む")
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
        /// URLより.packlinファイルをPackExportDTO形式で読み取る
        private func importPack(from url: URL) throws -> M1Pack {
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
            let orderedPacks = packs.sorted { $0.order < $1.order }
            let insertionIndex: Int = {
                switch insertionPosition {
                case .head:
                    // 日本語コメント：先頭挿入を選択している場合は index 0 を採用
                    return 0
                case .tail:
                    // 日本語コメント：末尾へ追加する設定なら既存数と同じ位置に挿入
                    return orderedPacks.count
                }
            }()
            let newOrder = sparseOrderForInsertion(items: orderedPacks, index: insertionIndex) {
                // 日本語コメント：挿入余白が尽きた際には正規化して順位を維持
                normalizeSparseOrders(orderedPacks)
            }
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
                    return String(localized: "取り込み完了")
                case .failure:
                    return String(localized: "取り込みに失敗しました")
                }
            }

            var message: String {
                switch self {
                case .success(let packName):
                    let format = String(localized: "%@ を取り込みました")
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
        
        // GALoggerのため変更前の設定値を記録する
        @State var ona_insertionPosition: InsertionPosition?
        @State var ona_showNeedWeight: Bool?
        @State var ona_weightDisplayInKg: Bool?
        @State var ona_linkCheckWithStock: Bool?
        @State var ona_footerMessage: Bool?
        
        var body: some View {

            VStack(alignment: .leading, spacing: 20) {
                // 新規追加の位置
                HStack(spacing: 8) {
                    Label {
                        Text("新規追加位置")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "plus.circle")
                            .symbolRenderingMode(.hierarchical)
                    }

                    Picker("新規追加位置", selection: $insertionPosition) {
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
                        Text("必要重量を表示")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // 重量計をKgで表示
                Toggle(isOn: $weightDisplayInKg) {
                    Label {
                        Text("重量計をKgで表示")
                            .font(.body)
                    } icon: {
                        Image(systemName: "scalemass.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                // チェックと在庫を連動
                Toggle(isOn: $linkCheckWithStock) {
                    Label {
                        Text("チェックと在庫を連動")
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
                        Text("フッターの説明文")
                            .font(.body)
                    } icon: {
                        ZStack{
                            Image(systemName: "platter.filled.bottom.iphone")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }
            .onAppear {
                // GALoggerのため変更前の設定値を記録する
                ona_insertionPosition  = insertionPosition
                ona_showNeedWeight     = showNeedWeight
                ona_weightDisplayInKg  = weightDisplayInKg
                ona_linkCheckWithStock = linkCheckWithStock
                ona_footerMessage      = footerMessage
            }
            .onDisappear {
                // 変更あればGALogger送信する
                if let ona = ona_insertionPosition, ona != insertionPosition {
                    GALogger.log(.function(name: "setting",
                                           option: "insertionPosition:"
                                                    + insertionPosition.rawValue))
                }
                if let ona = ona_showNeedWeight, ona != showNeedWeight {
                    GALogger.log(.function(name: "setting",
                                           option: "showNeedWeight:"
                                           + showNeedWeight.description))
                }
                if let ona = ona_weightDisplayInKg, ona != weightDisplayInKg {
                    GALogger.log(.function(name: "setting",
                                           option: "weightDisplayInKg:"
                                           + weightDisplayInKg.description))
                }
                if let ona = ona_linkCheckWithStock, ona != linkCheckWithStock {
                    GALogger.log(.function(name: "setting",
                                           option: "linkCheckWithStock:"
                                           + linkCheckWithStock.description))
                }
                if let ona = ona_footerMessage, ona != footerMessage {
                    GALogger.log(.function(name: "setting",
                                           option: "footerMessage:"
                                           + footerMessage.description))
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
                    Text("開発者を応援する")
                        .font(.body.weight(.medium))
                } icon: {
                    Image(systemName: "heart.fill")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.periodic(delay: 0.0)))
                }

                VStack(alignment: .leading, spacing: 16) {
                    // 広告を見て寄付する（ボタン）
                    Button(action: {
                        withAnimation {
                            // SafariでURLを表示する
                            showAd = true
                        }
                    }) {
                        Text("広告を見て寄付")
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
                                Text("動画広告を見て寄付")
                                    .frame(maxWidth: .infinity)

                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .imageScale(.small)
                                        .symbolRenderingMode(.hierarchical)
                                    Text("音が出る場合があります")
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
