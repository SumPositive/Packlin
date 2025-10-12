//
//  ChatGPTsheetView.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import SwiftUI
import SwiftData
import Foundation
import UIKit
import UniformTypeIdentifiers


/// パックをChatGPTで生成　シート
struct ChatGPTsheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                ChatGPTgeneratorView()
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(Text("app.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "setting.adClose")) {
                        dismiss()
                    }
                }
            }
        }
    }
}


/// ChatGPTと連携して .pack ファイルを生成・インポートするためのビュー
/// 設定画面からメイン画面のフッター下へ移動した要求に基づき、
/// 入力から送信、ファイルの取り込みまでをワンストップで提供する。
struct ChatGPTgeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    /// ユーザーがChatGPTへ伝えたい要件テキスト
    @State private var requirementText: String = ""
    /// ファイルアプリなどから生成済みJSONを選択する際のフラグ
    @State private var isPresentingImporter = false
    /// インポート処理やプロンプト転送の状態を伝えるためのアラート
    @State private var alertState: AlertState?

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ChatGPTへ渡すプロンプトを生成
    /// - 途中経過を表示せず、{name}.pack ファイル出力を明示的に依頼する指示を含める
    private var promptText: String {
        let trimmedRequirement = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requirement = trimmedRequirement.isEmpty ? "（ここにPackListへ追加したい荷物の要件を記入してください）" : trimmedRequirement

        return """
        # パックファイル生成依頼
        あなたはiOSアプリ「PackList」向けに荷物リストJSONを作成するアシスタントです。以下の制約と要件に従って単一JSONをUTF-8で出力してください。

        ## サンプル
        {
            "ProductName": "PackList_モチメモ",
            "copyright": "2025_sumpo@azukid.com",
            "version": "3.0",
            "name": "登山（デイハイク）",
            "memo": "日帰り登山装備。水2L、行動食、雨具必携",
            "createdAt": "2025-10-10T10:00:00Z",
            "groups": [
                {
                    "name": "💳 必須品",
                    "memo": "",
                    "items": [
                        {
                          "check": false,
                          "weight": 150,
                          "need": 1,
                          "name": "財布・身分証",
                          "memo": ""
                        }
                    ]
                }
            ]
        }

        ## 仕様
        - ルート要素には必ず次のプロパティを含める。
            - `ProductName`: "\(PACK_JSON_DTO_PRODUCT_NAME)"
            - `copyright`:"\(PACK_JSON_DTO_COPYRIGHT)"
            - `version`:"\(PACK_JSON_DTO_VERSION)"
        - ルート要素はパック1件のみ。構造は以下を厳守。
            - `name`: パック名。
            - `memo`: 補足メモ（空文字可）。
            - `createdAt`: ISO8601形式の日時文字列（例: 2024-05-01T10:00:00Z）。
            - `groups`: グループ配列。
        - 各グループには以下のプロパティを持たせる。
            - `name`: グループ名。
            - `memo`: グループの説明（空文字可）。
            - `items`: アイテム配列。
        - 各アイテムには以下のプロパティを持たせる。
            - `name`: アイテム名。
            - `memo`: 補足メモ（空文字可）。
            - `check`: 初期チェック状態（false）。
            - `need`: 必要数の整数。
            - `weight`: 重量(g)の整数。
        - `id`、`order`、`stock` といったアプリ内部で採番する値は出力しない。

        ## 出力形式
        - 途中経過や思考の説明は不要です。
        - 完成したJSONのみを `{パック名}.\(PACK_FILE_EXTENSION)` というパック・ファイルとして出力してください（ChatGPTアプリのファイル出力機能を使用）。
        - テキストの前置きや後置きは不要で、ファイル以外のレスポンスは避けてください。

        ## ユーザー要件
        \(requirement)

        以上を満たすパックを作成してください。
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // セクションタイトル
            Label {
                Text("chatgpt.title") //"ChatGPTに作ってもらおう")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }

            // 入力欄とプレースホルダー
            ZStack(alignment: .topLeading) {
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

                if isRequirementEmpty {
                    Text("例）夏の3泊4日キャンプ。家族4人（大人2人、子ども2人）用の持ち物を準備。食材は現地調達。雨天も想定。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                }
            }

            // 操作説明
            Text("入力した要件をChatGPTへ連携送信し、生成完了後に `{パック名}.pack` ファイルを保存してください。保存したファイルは下のボタンから取り込めます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // ChatGPT連携用ボタン群
            Button(action: sendPromptToChatGPTApp) {
                Label {
                    Text("ChatGPTに連携送信")
                        .font(.callout.weight(.semibold))
                } icon: {
                    Image(systemName: "paperplane")
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .disabled(isRequirementEmpty)
            
            Divider()
            
            Button(action: {
                // デフォルト引数を用いるためクロージャー越しにメソッドを呼び出す
                openChatGPTApp()
            }) {
                Label {
                    Text("ChatGPTアプリを開く")
                        .font(.callout.weight(.semibold))
                } icon: {
                    Image(systemName: "app.badge")
                        .symbolRenderingMode(.hierarchical)
                }
            }

            // JSON取り込みボタン
            Button(action: { isPresentingImporter = true }) {
                Label {
                    Text("生成した.packファイルを読み込む")
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
                allowedContentTypes: [PACK_FILE_UTTYPE],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let importedPack = try importPack(from: url)
                        // 取り込みに成功した場合は結果をアラートで共有
                        alertState = .importSuccess(packName: importedPack.name)
                    } catch {
                        debugPrint("Failed to import AI generated pack: \(error)")
                        // 失敗内容をそのまま表示して再試行してもらう
                        alertState = .importFailure(message: error.localizedDescription)
                    }
                case .failure(let error):
                    debugPrint("Failed to import AI generated pack: \(error)")
                    alertState = .importFailure(message: error.localizedDescription)
                }
            }

            Text("ChatGPTで生成された`.pack`ファイルをファイルアプリ等に保存し、このボタンから取り込むとパックとして追加されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.5 : 0.2), lineWidth: 0.5)
        )
        .alert(item: $alertState) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    /// 背景カラーをダーク／ライトに応じて出し分ける
    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(uiColor: .systemGray3)
        }

        return Color(uiColor: .systemGray6)
    }

    /// プロンプトをChatGPTアプリへ直接連携送信する
    private func sendPromptToChatGPTApp() {
        // 深い連携を行うために、まずは生成済みプロンプトを取得
        let prompt = promptText

        // ディープリンク処理は共通化したメソッドへ委譲し、保守性を高める
        openChatGPT(with: prompt)
    }

    /// ChatGPTアプリ（ユニバーサルリンク）を開く
    private func openChatGPTApp() {
        // プロンプト入力前にアプリだけ開きたいユーザー向けに、ベースURLのディープリンクを利用
        guard let url = URL(string: "https://chat.openai.com/") else {
            return
        }

        UIApplication.shared.open(url, options: [:]) { success in
            if success == false {
                alertState = .promptDeepLinkFailed
            }
        }
    }

    /// Web版ChatGPTをプロンプト付きで開く（ユニバーサルリンクでアプリにも遷移可能）
    /// - Parameter prompt: クエリとして渡したいプロンプト文字列
    private func openChatGPT(with prompt: String) {
        // URL生成が複数箇所に散らばらないよう、共通処理へ委譲
        guard let url = chatGPTDeepLinkURL(with: prompt) else {
            alertState = .promptEncodingFailed
            return
        }

        UIApplication.shared.open(url, options: [:]) { success in
            if success == false {
                alertState = .promptDeepLinkFailed
            }
        }
    }

    /// ChatGPTディープリンク用のURLを生成
    /// - Parameter prompt: クエリへ埋め込みたいテキスト
    /// - Returns: 生成に成功した場合はURL、失敗した場合はnil
    private func chatGPTDeepLinkURL(with prompt: String) -> URL? {
        // 公式仕様が開示されていないため、URLクエリに不向きな文字を個別に除外
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "#&=")

        // addingPercentEncoding が nil を返すケース（絵文字の組み合わせなど）を考慮
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return nil
        }

        // ChatGPT Web へのアクセスだが、ユニバーサルリンクによりアプリが起動するケースもある
        return URL(string: "https://chat.openai.com/?q=\(encoded)")
    }

    /// URLから .pack ファイルを読み込み、DTOチェック後にDBへ保存
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

        if dto.productName != PACK_JSON_DTO_PRODUCT_NAME {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "ProductName mismatch."])
        }
        if dto.copyright != PACK_JSON_DTO_COPYRIGHT {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Copyright mismatch."])
        }
        if dto.version != PACK_JSON_DTO_VERSION {
            throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Version mismatch."])
        }

        return try createPack(from: dto)
    }

    /// DTOからPackを作成してSwiftDataへ保存
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

    /// アラート表示用の状態定義
    private enum AlertState: Identifiable {
        /// インポート成功
        case importSuccess(packName: String)
        /// インポート失敗
        case importFailure(message: String)
        /// ディープリンクの起動に失敗した場合
        case promptDeepLinkFailed
        /// プロンプトのエンコードに失敗した場合
        case promptEncodingFailed

        var id: String {
            switch self {
            case .importSuccess(let packName):
                return "ai-success-\(packName)"
            case .importFailure:
                return "ai-failure"
            case .promptDeepLinkFailed:
                return "ai-prompt-deeplink"
            case .promptEncodingFailed:
                return "ai-prompt-encoding"
            }
        }

        var title: String {
            switch self {
            case .importSuccess:
                return String(localized: "setting.import.success.title")
            case .importFailure:
                return String(localized: "setting.import.error.title")
            case .promptDeepLinkFailed:
                return "ChatGPTを開けませんでした"
            case .promptEncodingFailed:
                return "プロンプトの準備に失敗しました"
            }
        }

        var message: String {
            switch self {
            case .importSuccess(let packName):
                let format = String(localized: "setting.import.success.message")
                return String(format: format, packName)
            case .importFailure(let message):
                return message
            case .promptDeepLinkFailed:
                return "ネットワーク接続やChatGPTアプリの状態を確認し、再度お試しください。"
            case .promptEncodingFailed:
                return "入力内容に特殊な文字が含まれている可能性があります。手動でコピーして送信してください。"
            }
        }
    }
}
