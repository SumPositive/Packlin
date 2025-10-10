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
import UIKit

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
                    // ChatGPT連携でPackList.jsonをつくる
                    AIAssistedImportView()
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
            // 共有 Pack_*.json を読み込む
            Button(action: {
                isPresentingImporter = true
            }) {
                Label {
                    Text("action.json.download")
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
                allowedContentTypes: [.json],
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
        /// URLよりJSONファイルをPackExportDTO形式で読み取る
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
    
    /// ChatGPT連携でPackList.jsonを生成して読み込む補助ビュー
    struct AIAssistedImportView: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(\.openURL) private var openURL

        // ユーザーが入力する要件テキスト
        @State private var requirementText: String = ""
        // ファイルアプリから生成済みjsonをインポートする際に使用
        @State private var isPresentingImporter = false
        // インポート結果のアラート制御
        @State private var importAlert: ImportAlert?
        // プロンプトをコピーした際の簡易トースト表示制御
        @State private var showCopiedToast = false

        // ユーザー入力が空かどうかを判定（ボタン制御などで使用）
        private var isRequirementEmpty: Bool {
            requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // ChatGPTへ渡す完全なプロンプト文字列を生成
        private var promptText: String {
            let trimmed = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
            let userRequirement = trimmed.isEmpty ? "（ここにPackListへ追加したい荷物の要件を記入してください）" : trimmed

            // ChatGPTが期待通りのjsonを出力できるよう詳細な仕様を含める
            return """
            # PackList.json生成依頼
            あなたはiOSアプリ「PackList」向けに荷物リストJSONを作成するアシスタントです。以下の制約と要件に従って `PackList.json` 相当の単一JSONをUTF-8で出力してください。

            ## 仕様
            - フィールド `copyright` は必ず "\(PACK_JSON_DTO_COPYRIGHT)"。
            - フィールド `version` は必ず "\(PACK_JSON_DTO_VERSION)"。
            - ルート要素はパック1件のみ。構造は以下を厳守。
                - `id`: 任意のUUID文字列（ダミーで可）。
                - `order`: 0 から始まる整数。グループ・アイテムも同様に昇順となるよう設定。
                - `name`: パック名。
                - `memo`: 補足メモ（空文字可）。
                - `createdAt`: ISO8601形式の日時文字列（例: 2024-05-01T10:00:00Z）。
                - `groups`: グループ配列。
            - 各グループには以下のプロパティを持たせる。
                - `id`: 任意のUUID文字列。
                - `order`: パック内での表示順を表す整数。0, 1000, 2000 ... と等間隔にしておくと安全。
                - `name`: グループ名。
                - `memo`: グループの説明（空文字可）。
                - `items`: アイテム配列。
            - 各アイテムには以下のプロパティを持たせる。
                - `id`: 任意のUUID文字列。
                - `order`: グループ内での表示順。0, 1000, 2000 ... のように昇順となる整数。
                - `name`: アイテム名。
                - `memo`: 補足メモ（空文字可）。
                - `check`: 初期チェック状態（true または false）。
                - `stock`: 所持数の整数。
                - `need`: 必要数の整数。
                - `weight`: 重量(g)の整数。

            ## 注意事項
            - 追加の文章は一切出力せず、JSON文字列のみを返してください。
            - JSONは可読性のためインデントして構いませんが、ルートはオブジェクト1つのみとします。
            - `need` や `weight` が未定の場合でも 0 を設定してください。

            ## ユーザー要件
            \(userRequirement)

            以上を満たすJSONを作成してください。
            """
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                // セクションタイトル
                Label {
                    Text("ChatGPTでPackList.jsonを作成")
                        .font(.body.weight(.bold))
                } icon: {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                }

                // 入力欄をZStackで包み、プレースホルダーを手動表示
                ZStack(alignment: .topLeading) {
                    if isRequirementEmpty {
                        Text("例）夏の3泊4日キャンプ。家族4人（大人2人、子ども2人）用の持ち物を準備。食材は現地調達。雨天も想定。")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 10)
                    }

                    TextEditor(text: $requirementText)
                        .frame(minHeight: 140, maxHeight: 200)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .accessibilityLabel(Text("PackListの要件入力"))
                }

                // 補足テキストで操作の流れを説明
                Text("入力した要件をもとにプロンプトを生成し、ChatGPTアプリへ共有できます。生成後に受け取った `PackList.json` を下部のインポートボタンで読み込んでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                // プロンプトに関する操作ボタン群
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: copyPromptToClipboard) {
                        Label {
                            Text("プロンプトをコピー")
                                .font(.callout.weight(.semibold))
                        } icon: {
                            Image(systemName: "doc.on.doc")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }

                    ShareLink(item: promptText, preview: SharePreview("PackList.json Prompt")) {
                        Label {
                            Text("ChatGPTに共有")
                                .font(.callout.weight(.semibold))
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .disabled(isRequirementEmpty)

                    Button(action: openChatGPTApp) {
                        Label {
                            Text("ChatGPTアプリを開く")
                                .font(.callout.weight(.semibold))
                        } icon: {
                            Image(systemName: "app.badge")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }

                // コピー完了の簡易表示
                if showCopiedToast {
                    Text("プロンプトをコピーしました。ChatGPTへ貼り付けてください。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                Divider()

                // JSON取り込みボタン
                Button(action: { isPresentingImporter = true }) {
                    Label {
                        Text("生成したPackList.jsonを読み込む")
                            .font(.callout.weight(.semibold))
                    } icon: {
                        Image(systemName: "tray.and.arrow.down")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .fileImporter(
                    isPresented: $isPresentingImporter,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        do {
                            let importedPack = try importPack(from: url)
                            importAlert = .success(packName: importedPack.name)
                        } catch {
                            debugPrint("Failed to import AI generated pack: \(error)")
                            importAlert = .failure(message: error.localizedDescription)
                        }
                    case .failure(let error):
                        debugPrint("Failed to import AI generated pack: \(error)")
                        importAlert = .failure(message: error.localizedDescription)
                    }
                }

                Text("ChatGPTで生成されたJSONファイルをファイルアプリ等に保存し、このボタンから取り込むとパックとして追加されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .alert(item: $importAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }

        // プロンプトをクリップボードへコピーし、短時間トーストを表示
        private func copyPromptToClipboard() {
            UIPasteboard.general.string = promptText
            withAnimation {
                showCopiedToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showCopiedToast = false
                }
            }
        }

        // ChatGPTアプリ（存在しない場合はWeb）を開く
        private func openChatGPTApp() {
            guard let appURL = URL(string: "chatgpt://") else { return }
            let result = openURL(appURL)
            if result == .handled {
                return
            }
            guard let webURL = URL(string: "https://chat.openai.com/") else { return }
            _ = openURL(webURL)
        }

        // URLからPackList.jsonを読み込み、DTOチェック後にDBへ保存
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

            if dto.copyright != PACK_JSON_DTO_COPYRIGHT {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Copyright mismatch."])
            }
            if dto.version != PACK_JSON_DTO_VERSION {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Version mismatch."])
            }

            return try createPack(from: dto)
        }

        // DTOからPackを作成してSwiftDataへ保存
        private func createPack(from dto: PackJsonDTO) throws -> M1Pack {
            let descriptor = FetchDescriptor<M1Pack>()
            let packs = (try? modelContext.fetch(descriptor)) ?? []
            let newOrder = M1Pack.nextPackOrder(packs)

            modelContext.undoManager?.groupingBegin()
            defer {
                modelContext.undoManager?.groupingEnd()
            }

            return PackImporter.insertPack(from: dto, into: modelContext, order: newOrder)
        }

        // インポート結果を表示するアラート
        private enum ImportAlert: Identifiable {
            case success(packName: String)
            case failure(message: String)

            var id: String {
                switch self {
                case .success(let packName):
                    return "ai-success-\(packName)"
                case .failure:
                    return "ai-failure"
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
