//
//  ChatGPTPackGeneratorView.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation
import UIKit

/// PackList.json をChatGPTと連携しながら生成・インポートするためのビュー
/// 設定画面からメイン画面のフッター下へ移動した要求に基づき、
/// 入力から送信、ファイルの取り込みまでをワンストップで提供する。
struct ChatGPTPackGeneratorView: View {
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
    /// - 途中経過を表示せず、PackList.json ファイル出力を明示的に依頼する指示を含める
    private var promptText: String {
        let trimmedRequirement = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requirement = trimmedRequirement.isEmpty ? "（ここにPackListへ追加したい荷物の要件を記入してください）" : trimmedRequirement

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

        ## 出力形式
        - 途中経過や思考の説明は不要です。
        - 完成したJSONのみを `PackList.json` というファイルとして出力してください（ChatGPTアプリのファイル出力機能を使用）。
        - テキストの前置きや後置きは不要で、ファイル以外のレスポンスは避けてください。

        ## ユーザー要件
        \(requirement)

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

            // 入力欄とプレースホルダー
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

            // 操作説明
            Text("入力した要件をChatGPTへ連携送信し、生成完了後に `PackList.json` ファイルを保存してください。保存したファイルは下のボタンから取り込めます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // ChatGPT連携用ボタン群
            VStack(alignment: .leading, spacing: 12) {
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

            Text("ChatGPTで生成されたJSONファイルをファイルアプリ等に保存し、このボタンから取り込むとパックとして追加されます。")
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
        // ここで生成したプロンプトを多種のペーストボード形式で書き込み
        // ChatGPTアプリが独自UTIを参照している可能性にも備える
        let prompt = promptText
        UIPasteboard.general.string = prompt
        UIPasteboard.general.setItems([
            [
                UTType.utf8PlainText.identifier: prompt,
                "com.openai.chat.prompt": prompt
            ]
        ], options: [
            .localOnly: false,
            .expirationDate: Date().addingTimeInterval(60)
        ])

        // URLエンコードに利用する文字集合を作成
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "#&=")

        // URLパラメータ化に失敗した場合はユーザーへ伝えて処理終了
        guard let encodedPrompt = prompt.addingPercentEncoding(withAllowedCharacters: allowed) else {
            alertState = .promptEncodingFailed
            return
        }

        // ChatGPTアプリ側のディープリンク仕様は変更される可能性があるため
        // 複数の候補URLを優先度順に試行する
        let candidateSchemes: [String] = [
            "chatgpt://chat/share?text=\(encodedPrompt)",
            "chatgpt://chat?text=\(encodedPrompt)",
            "chatgpt://compose?input=\(encodedPrompt)",
            "chatgpt://conversation/new?message=\(encodedPrompt)"
        ]

        for scheme in candidateSchemes {
            guard let url = URL(string: scheme) else {
                continue
            }

            if UIApplication.shared.canOpenURL(url) {
                // アプリを開く前に、ペーストボードへ格納済みであることをユーザーへ通知
                alertState = .promptClipboardPreparedForApp

                // open(_:options:completionHandler:) を利用して
                // 成功判定と失敗時のフォールバックを細かく制御する
                UIApplication.shared.open(url, options: [:]) { success in
                    if success {
                        return
                    }

                    openChatGPTApp(copyPromptForWeb: true)
                }
                return
            }
        }

        // どのスキームも利用できなかった場合は通常のアプリ（またはWeb）起動へ
        openChatGPTApp(copyPromptForWeb: true)
    }

    /// ChatGPTアプリ（存在しない場合はWeb版）を開く
    private func openChatGPTApp(copyPromptForWeb: Bool = false) {
        guard let appURL = URL(string: "chatgpt://") else {
            return
        }

        if UIApplication.shared.canOpenURL(appURL) {
            // ChatGPT純正アプリが存在する場合はこちらを最優先で起動
            UIApplication.shared.open(appURL)
            return
        }

        guard let webURL = URL(string: "https://chat.openai.com/") else {
            return
        }

        if copyPromptForWeb {
            // Web版利用時にすぐ貼り付けられるようクリップボードへコピー
            UIPasteboard.general.string = promptText
            alertState = .promptClipboardCopied
        }

        // アプリが無い場合はWeb版へ誘導
        UIApplication.shared.open(webURL)
    }

    /// URLからPackList.jsonを読み込み、DTOチェック後にDBへ保存
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
        /// プロンプトをクリップボードへコピーしたことを通知
        case promptClipboardCopied
        /// ChatGPTアプリへ貼り付けできる形でプロンプトを準備済みであることを通知
        case promptClipboardPreparedForApp
        /// プロンプトのエンコードに失敗した場合
        case promptEncodingFailed

        var id: String {
            switch self {
            case .importSuccess(let packName):
                return "ai-success-\(packName)"
            case .importFailure:
                return "ai-failure"
            case .promptClipboardCopied:
                return "ai-prompt-copied"
            case .promptClipboardPreparedForApp:
                return "ai-prompt-app"
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
            case .promptClipboardCopied:
                return "プロンプトをコピーしました"
            case .promptClipboardPreparedForApp:
                return "ChatGPTにプロンプトを送信しました"
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
            case .promptClipboardCopied:
                return "ChatGPT Web を開いたらペーストしてください。"
            case .promptClipboardPreparedForApp:
                return "ChatGPTアプリがペーストを求めた場合は、そのまま貼り付けてください。"
            case .promptEncodingFailed:
                return "入力内容に特殊な文字が含まれている可能性があります。手動でコピーして送信してください。"
            }
        }
    }
}
