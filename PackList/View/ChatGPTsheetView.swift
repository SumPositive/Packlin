//
//  ChatGPTsheetView.swift
//  PackList
//
//  Created by OpenAI Assistant on 2025/??/??.
//

import SwiftUI
import SwiftData
import Foundation


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


/// ChatGPTと連携して .pack ファイルを生成するためのビュー
/// 設定画面からメイン画面のフッター下へ移動した要求に基づき、
/// アプリ内生成とクレジット購入をまとめて提供する。
struct ChatGPTgeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var creditStore: CreditStore

    /// ユーザーがChatGPTへ伝えたい要件テキスト
    @State private var requirementText: String = ""
    /// インポート処理やプロンプト転送の状態を伝えるためのアラート
    @State private var alertState: AlertState?
    /// azuki-api経由の生成リクエスト中であることを示すフラグ
    @State private var isGenerating = false
    /// アプリ内でクレジット購入を行う際の進行中商品ID（nilなら待機中）
    @State private var processingProductId: String?

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

            // 操作説明（アプリ内生成の流れを簡潔に案内）
            Text("ご要望を入力して「AIに作ってもらう」を押してください。AI利用券を1枚使います")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            // アプリ内で直接OpenAIへ問い合わせる操作
//            VStack(alignment: .leading, spacing: 4) {
//                Text("アプリ内で生成（回数券1枚消費）")
//                    .font(.subheadline.weight(.semibold))
//                Text("回数券残り: \(creditStore.credits) / 消費: \(CHATGPT_GENERATION_CREDIT_COST)")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//            }

            Button(action: generatePackWithOpenAI) {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(isGenerating ? "お作りしています..." : "AIに作ってもらう")
                        .font(.callout.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isRequirementEmpty || isGenerating)

            if isGenerating {
                Text("AIへ依頼中です。もう少しお待ちください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 回数券購入
            creditPurchaseMenu
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

    /// azuki-api経由でOpenAIにパック生成を依頼する
    private func generatePackWithOpenAI() {
        let trimmedRequirement = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRequirement.isEmpty {
            alertState = .generationFailure(message: "ご要望を入れてください。")
            return
        }
        if creditStore.credits < CHATGPT_GENERATION_CREDIT_COST {
            alertState = .creditShortage
            return
        }

        isGenerating = true
        Task {
            do {
                let dto = try await AzukiAPIClient.shared.generatePack(requirement: trimmedRequirement)
                try await MainActor.run {
                    do {
                        let importedPack = try createPack(from: dto)
                        do {
                            try creditStore.consume(credits: CHATGPT_GENERATION_CREDIT_COST)
                        } catch {
                            alertState = .creditShortage
                            return
                        }
                        alertState = .generationSuccess(packName: importedPack.name)
                    } catch {
                        let message: String
                        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                            message = description
                        } else {
                            message = error.localizedDescription
                        }
                        alertState = .generationFailure(message: message)
                    }
                }
            } catch {
                await MainActor.run {
                    let message: String
                    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                        message = description
                    } else {
                        message = "AIが忙しいようです。時間をおいて再度お試しください"
                    }
                    alertState = .generationFailure(message: message)
                }
            }
            await MainActor.run {
                isGenerating = false
            }
        }
    }

    /// クレジット購入
    /// - Parameter option: Configで定義したオプションタプル
    private func purchaseCredits(option: (productId: String, priceYen: Int, credits: Int)) {
        processingProductId = option.productId
        Task {
            do {
                let added = try await AzukiAPIClient.shared.purchaseCredits(productId: option.productId)
                await MainActor.run {
                    creditStore.add(credits: added)
                    alertState = .purchaseSuccess(added: added, priceYen: option.priceYen)
                }
            } catch {
                await MainActor.run {
                    let message: String
                    if let apiError = error as? LocalizedError, let description = apiError.errorDescription {
                        message = description
                    } else {
                        message = "AI利用券の購入ができません。時間を空けて再度お試しください"
                    }
                    alertState = .purchaseFailure(message: message)
                }
            }
            await MainActor.run {
                processingProductId = nil
            }
        }
    }

    /// クレジット購入UIのまとまり
    private var creditPurchaseMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("AI利用券購入")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "cart")
                    .symbolRenderingMode(.hierarchical)
            }

            Text("AI利用券残り: \(creditStore.credits)")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Config側で定義した金額・クレジットの対応表をそのまま描画する
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AZUKI_CREDIT_PURCHASE_OPTIONS, id: \.productId) { option in
                    Button {
                        purchaseCredits(option: option)
                    } label: {
                        HStack(spacing: 12) {
                            if processingProductId == option.productId {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text("AI利用券\(option.credits)枚：¥\(option.priceYen)")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor.opacity(0.8))
                    .disabled(processingProductId != nil)
                }
            }
        }
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
        /// azuki-api経由での生成が成功した場合
        case generationSuccess(packName: String)
        /// azuki-api経由での生成が失敗した場合
        case generationFailure(message: String)
        /// クレジットが不足している場合
        case creditShortage
        /// クレジット購入が成功した場合
        case purchaseSuccess(added: Int, priceYen: Int)
        /// クレジット購入が失敗した場合
        case purchaseFailure(message: String)

        var id: String {
            switch self {
            case .generationSuccess(let packName):
                return "ai-generation-success-\(packName)"
            case .generationFailure(let message):
                return "ai-generation-failure-\(message)"
            case .creditShortage:
                return "ai-credit-shortage"
            case .purchaseSuccess(let added, let priceYen):
                return "ai-purchase-success-\(added)-\(priceYen)"
            case .purchaseFailure(let message):
                return "ai-purchase-failure-\(message)"
            }
        }

        var title: String {
            switch self {
            case .generationSuccess:
                return "生成完了"
            case .generationFailure:
                return "生成に失敗しました"
            case .creditShortage:
                return "AI利用券不足"
            case .purchaseSuccess:
                return "購入完了"
            case .purchaseFailure:
                return "購入失敗"
            }
        }

        var message: String {
            switch self {
            case .generationSuccess(let packName):
                return "パック『\(packName)』を追加しました。"
            case .generationFailure(let message):
                return message
            case .creditShortage:
                return "AI利用券が不足しています。下の購入メニューから購入してください"
            case .purchaseSuccess(let added, let priceYen):
                return "¥\(priceYen)の購入でAI利用券を\(added)追加しました。"
            case .purchaseFailure(let message):
                return message
            }
        }
    }
}
