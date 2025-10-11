//
//  ChatGPTPackGeneratorView.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import SwiftUI
import SwiftData
import Foundation
import UniformTypeIdentifiers

/// ChatGPT(OpenAI API)と連携して .pack ファイル相当のデータを生成・即時取り込みするビュー
/// - 旧来のディープリンク手順を廃し、アプリ内で完結する体験へ刷新する。
struct ChatGPTPackGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    /// ユーザーがChatGPTへ伝えたい要件テキスト
    @State private var requirementText: String = ""
    /// ファイルアプリなどから生成済みJSONを選択する際のフラグ（手動インポート用）
    @State private var isPresentingImporter = false
    /// インポート処理やAPI連携の結果を表示するアラート
    @State private var alertState: AlertState?
    /// OpenAI APIへリクエスト中かどうかのフラグ
    @State private var isGenerating = false
    /// 直近に生成できたパック名を記録して、ユーザーへフィードバックする
    @State private var lastGeneratedPackName: String?

    /// OpenAI APIキーはUserDefaults(AppStorage)へ保存し、次回以降の入力を省く
    @AppStorage(AppStorageKey.openAIAPIKey) private var openAIAPIKey: String = ""
    /// Info.plistのバンドル値を一度だけ読み込んだかを記録するフラグ
    @State private var didApplyBundledAPIKey = false

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// トリム済みのAPIキーを取得（前後スペースの混入を排除）
    private var trimmedAPIKey: String {
        openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 生成ボタンを活性化できる条件
    private var canRequestGeneration: Bool {
        isRequirementEmpty == false && trimmedAPIKey.isEmpty == false && isGenerating == false
    }

    /// プロンプトを生成
    private func promptText(for requirement: String) -> String {
        let requirementBlock = requirement.isEmpty
            ? "（ここにPackListへ追加したい荷物の要件を記入してください）"
            : requirement

        return """
        # パックファイル生成依頼
        あなたはiOSアプリ「PackList」向けに荷物リストJSONを作成するアシスタントです。以下の制約と要件に従って単一JSONオブジェクトをUTF-8で出力してください。

        ## 仕様
        - ルート要素には必ず次のプロパティを含める。
            - `ProductName`: "\(PACK_JSON_DTO_PRODUCT_NAME)"
            - `copyright`: "\(PACK_JSON_DTO_COPYRIGHT)"
            - `version`: "\(PACK_JSON_DTO_VERSION)"
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
        - JSON以外のテキストを含めず、追加のコメントも避けてください。

        ## ユーザー要件
        \(requirementBlock)

        以上を満たす単一のJSONオブジェクトを生成してください。
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // セクションタイトル
            Label {
                Text("ChatGPTでパックを作成")
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

            // OpenAI APIの説明
            Text("入力内容をOpenAI APIへ送信して荷物リストを自動生成し、そのままPackListへ取り込みます。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                // APIキー入力欄
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI APIキー")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("sk-...", text: $openAIAPIKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textContentType(.password)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                Text("APIキーは端末内の設定(AppStorage)に暗号化せず保存されます。セキュリティポリシーに応じて適切に管理してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: requestGeneration) {
                    Label {
                        Text(isGenerating ? "生成中..." : "OpenAI APIでパックを生成")
                            .font(.callout.weight(.semibold))
                    } icon: {
                        Image(systemName: isGenerating ? "hourglass" : "wand.and.stars")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .disabled(canRequestGeneration == false)

                if isGenerating {
                    ProgressView("OpenAI APIに問い合わせ中...")
                        .progressViewStyle(.circular)
                }

                if let lastGeneratedPackName {
                    Text("直近に追加したパック: \(lastGeneratedPackName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Info.plistにOpenAI APIキーを記載するとアプリ解析で第三者に露見する恐れがあります。公開ビルドでは必ずKeychainや自社サーバー経由の配布に切り替えてください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Divider()

            // JSON取り込みボタン（従来方式のフォールバック）
            Button(action: { isPresentingImporter = true }) {
                Label {
                    Text("生成済み.packファイルを読み込む")
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
                        alertState = .importSuccess(packName: importedPack.name)
                    } catch {
                        debugPrint("Failed to import AI generated pack: \(error)")
                        alertState = .importFailure(message: error.localizedDescription)
                    }
                case .failure(let error):
                    debugPrint("Failed to import AI generated pack: \(error)")
                    alertState = .importFailure(message: error.localizedDescription)
                }
            }

            Text("OpenAI APIが利用できない場合は、手動で生成した`.pack`ファイルをここから取り込めます。")
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
        .onAppear {
            applyBundledAPIKeyIfNeeded()
        }
    }

    /// 背景カラーをダーク／ライトに応じて出し分ける
    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(uiColor: .systemGray3)
        }

        return Color(uiColor: .systemGray6)
    }

    /// Info.plistへバンドルされたAPIキーを一度だけUserDefaultsへコピーする
    private func applyBundledAPIKeyIfNeeded() {
        // 多重呼び出しを避けて不要な再代入を防ぐ
        if didApplyBundledAPIKey {
            return
        }

        didApplyBundledAPIKey = true

        // すでにユーザー入力済みならバンドル値で上書きしない
        if openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return
        }

        // Info.plistの値が存在すればコピーする（開発・デモ用途のみ想定）
        if let bundledKey = InfoPlistSecrets.shared.bundledOpenAIAPIKey {
            openAIAPIKey = bundledKey
        }
    }

    /// OpenAI APIへパック生成を依頼
    private func requestGeneration() {
        if isGenerating {
            return
        }

        let trimmedRequirement = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRequirement.isEmpty {
            alertState = .missingRequirement
            return
        }

        if trimmedAPIKey.isEmpty {
            alertState = .missingAPIKey
            return
        }

        isGenerating = true
        Task {
            await generatePack(with: trimmedRequirement)
        }
    }

    /// 実際にOpenAI APIへアクセスしてPackを生成・取り込みする
    @MainActor
    private func generatePack(with requirement: String) async {
        defer {
            isGenerating = false
        }

        let prompt = promptText(for: requirement)
        let generator = OpenAIPackGenerator(apiKey: trimmedAPIKey)

        do {
            let dto = try await generator.generatePack(using: prompt)
            let importedPack = try createPack(from: dto)
            lastGeneratedPackName = importedPack.name
            alertState = .apiSuccess(packName: importedPack.name)
            requirementText = ""
        } catch let error as OpenAIPackGenerator.GeneratorError {
            alertState = .apiFailure(message: error.localizedDescription)
        } catch {
            alertState = .apiFailure(message: error.localizedDescription)
        }
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
        let decoder = PackJSONDecoderFactory.decoder()
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
        /// インポート成功（手動）
        case importSuccess(packName: String)
        /// インポート失敗（手動）
        case importFailure(message: String)
        /// APIでの生成が成功した場合
        case apiSuccess(packName: String)
        /// APIで失敗した場合
        case apiFailure(message: String)
        /// APIキー未入力
        case missingAPIKey
        /// 要件未入力
        case missingRequirement

        var id: String {
            switch self {
            case .importSuccess(let packName):
                return "ai-import-success-\(packName)"
            case .importFailure:
                return "ai-import-failure"
            case .apiSuccess(let packName):
                return "ai-api-success-\(packName)"
            case .apiFailure:
                return "ai-api-failure"
            case .missingAPIKey:
                return "ai-missing-key"
            case .missingRequirement:
                return "ai-missing-requirement"
            }
        }

        var title: String {
            switch self {
            case .importSuccess, .apiSuccess:
                return String(localized: "setting.import.success.title")
            case .importFailure, .apiFailure:
                return String(localized: "setting.import.error.title")
            case .missingAPIKey:
                return "OpenAI APIキーが未入力です"
            case .missingRequirement:
                return "要件が入力されていません"
            }
        }

        var message: String {
            switch self {
            case .importSuccess(let packName), .apiSuccess(let packName):
                let format = String(localized: "setting.import.success.message")
                return String(format: format, packName)
            case .importFailure(let message), .apiFailure(let message):
                return message
            case .missingAPIKey:
                return "OpenAIの管理画面から取得したAPIキーを入力してください。"
            case .missingRequirement:
                return "生成したい荷物リストの条件を入力してから再度お試しください。"
            }
        }
    }
}
