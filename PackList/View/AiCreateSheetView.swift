//
//  AiCreateSheetView.swift
//  PackList
//
//  Created by sumpo on 2025/10/12.
//

import SwiftUI
import SwiftData
import Foundation
import StoreKit


/// パックをAIで生成　シート
struct AiCreateSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                AiCreateView()
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


/// AIで新しいパックを生成するためのビュー
struct AiCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var creditStore: CreditStore

    /// ユーザーからAIへの要望・要件テキスト
    /// AppStorageを利用してシートを閉じても入力内容を保持する
    @AppStorage(AppStorageKey.aiRequirementText) private var requirementText: String = ""
    /// インポート処理やプロンプト転送の状態を伝えるためのアラート
    @State private var alertState: AlertState?
    /// azuki-apiリクエスト中であることを示すフラグ
    @State private var isGenerating = false
    /// アプリ内でクレジット購入を行う際の進行中商品ID（nilなら待機中）
    @State private var processingProductId: String?
    /// StoreKit 2 で取得した商品情報をキャッシュしておき、複数回の購入ボタンタップで再利用する
    @State private var storeProducts: [Product] = []

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // セクションタイトル
            Label {
                Text("ai.create.title") //"AIにパックを作ってもらおう")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }

            // 操作説明（アプリ内生成の流れを簡潔に案内）
            Text("ai.create.instructions") //要望を入力して「AIに作ってもらう」を押してください。AI利用券を1枚使います
                .font(.body)
                .foregroundStyle(.secondary)
            
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
                    .accessibilityLabel(Text("ai.create.accessibility")) //"PackListの要件入力"

                if isRequirementEmpty {
                    // 入力例
                    //　　　例）夏の3泊4日キャンプ
                    //　　　家族4人（大人2人、子ども2人）用の持ち物を準備
                    //　　　食材は現地調達
                    //　　　雨天も想定
                    Text("""
                        例）夏の3泊4日キャンプ。
                        家族4人（大人2人、子ども2人）用の持ち物を準備。
                        食材は現地調達。
                        雨天も想定。
                        """)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                }
            }

            Button {
                generatePackWithOpenAI()
            } label: {
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
        .task {
            await refreshCreditBalance()
            await loadProductsIfNeeded()
        }
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

    /// サーバーからクレジット残高を取得してローカルに反映する
    private func refreshCreditBalance() async {
        // 必要なときだけサーバーへ問い合わせるための共通関数
        let userId = await MainActor.run { creditStore.userId }
        do {
            let remoteBalance = try await AzukiApi.shared.fetchCreditBalance(userId: userId)
            await MainActor.run {
                creditStore.overwrite(credits: remoteBalance)
            }
        } catch {
            #if DEBUG
            print("credit refresh failed: \(error)")
            #endif
        }
    }

    /// azuki-api経由でOpenAIにパック生成を依頼する
    private func generatePackWithOpenAI() {
        let trimmedRequirement = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRequirement.isEmpty {
            alertState = .generationFailure(message: "ご要望を入れてください。")
            return
        }

        let userId = creditStore.userId
        isGenerating = true
        Task {
            // deferで生成処理終了後の共通後片付け（ローカル残高の戻しとローディング解除）をまとめる
            let cost = CHATGPT_GENERATION_CREDIT_COST
            var shouldRestoreCredits = false
            defer {
                Task {
                    await MainActor.run {
                        if shouldRestoreCredits {
                            // サーバー側で消費されなかったと推定される場合はローカル残高を戻す
                            creditStore.add(credits: cost)
                        }
                        isGenerating = false
                    }
                }
            }

            // ローカル残高が不足している場合のみサーバーに問い合わせ、無駄な通信を避ける
            let hasEnoughCredits = await ensureSufficientCreditsForGeneration(cost: cost)
            if hasEnoughCredits == false {
                await MainActor.run {
                    alertState = .creditShortage
                }
                return
            }

            do {
                try await MainActor.run {
                    try creditStore.consume(credits: cost)
                    shouldRestoreCredits = true
                }
            } catch {
                await MainActor.run {
                    alertState = .creditShortage
                }
                return
            }

            do {
                let dto = try await AzukiApi.shared.generatePack(userId: userId, requirement: trimmedRequirement)
                // サーバー側ではすでにクレジットが消費済みとみなし、戻しは行わない
                shouldRestoreCredits = false
                do {
                    let packName = try await MainActor.run { () -> String in
                        let importedPack = try createPack(from: dto)
                        return importedPack.name
                    }
                    await MainActor.run {
                        alertState = .generationSuccess(packName: packName)
                    }
                } catch {
                    let message: String
                    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                        message = description
                    } else {
                        message = error.localizedDescription
                    }
                    await MainActor.run {
                        alertState = .generationFailure(message: message)
                    }
                }
            } catch let apiError as AzukiAPIError {
                // API起因のエラーは内容に応じて処理。ローカル残高はdeferで戻す。
                if case .insufficientCredits = apiError {
                    // サーバー側でも不足判定となったのでローカルを戻さず、最新残高を取得して同期する
                    shouldRestoreCredits = false
                    await refreshCreditBalance()
                    await MainActor.run {
                        alertState = .creditShortage
                    }
                } else {
                    let message = apiError.errorDescription ?? "AIが忙しいようです。時間をおいて再度お試しください"
                    await MainActor.run {
                        alertState = .generationFailure(message: message)
                    }
                }
            } catch let localized as LocalizedError {
                let message = localized.errorDescription ?? localized.localizedDescription
                await MainActor.run {
                    alertState = .generationFailure(message: message)
                }
            } catch {
                await MainActor.run {
                    alertState = .generationFailure(message: "AIが忙しいようです。時間をおいて再度お試しください")
                }
            }
        }
    }

    /// クレジット購入
    /// - Parameter option: Configで定義したオプションタプル
    private func purchaseCredits(option: (productId: String, priceYen: Int, credits: Int)) {
        Task {
            await MainActor.run {
                // 複数ボタンが並ぶため、購入中の選択肢のみローディング表示へ切り替える
                processingProductId = option.productId
            }

            do {
                // 1. StoreKit2 から商品情報を取得（初回のみネットワーク越し）
                await loadProductsIfNeeded()
                let product = try await fetchProduct(matching: option.productId)

                // 2. ユーザーに課金ダイアログを提示
                let outcome = try await product.purchase()

                switch outcome {
                case .success(let verificationResult):
                    // 3. トランザクション署名を検証し、サーバーへレシートを送信
                    let transaction = try await resolveVerifiedTransaction(from: verificationResult)
                    let serverResult = try await registerPurchaseOnServer(option: option, transaction: transaction)
                    await finalizePurchase(option: option, transaction: transaction, serverResult: serverResult)

                case .pending:
                    // ファミリー共有などで承認待ちになる場合
                    await MainActor.run {
                        alertState = .purchaseFailure(message: "購入が承認待ちです。承認が完了すると自動で反映されます。")
                    }

                case .userCancelled:
                    // ユーザーがキャンセルした場合は状況を伝えるメッセージを表示
                    await MainActor.run {
                        alertState = .purchaseFailure(message: "購入をキャンセルしました。必要であれば再度お試しください。")
                    }

                @unknown default:
                    await MainActor.run {
                        alertState = .purchaseFailure(message: "想定外の購入結果が返りました。時間をおいて再度お試しください。")
                    }
                }
            } catch let flowError as PurchaseFlowError {
                await MainActor.run {
                    let message = flowError.errorDescription ?? "AI利用券の購入に失敗しました。"
                    alertState = .purchaseFailure(message: message)
                }
            } catch let localized as LocalizedError {
                await MainActor.run {
                    let message = localized.errorDescription ?? localized.localizedDescription
                    alertState = .purchaseFailure(message: message)
                }
            } catch {
                await MainActor.run {
                    alertState = .purchaseFailure(message: "AI利用券の購入中にエラーが発生しました。通信環境をご確認ください。")
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

    /// StoreKit 2 から商品情報を取得し、`storeProducts` へキャッシュする
    /// - Note: 初期表示時にまとめて取得し、以降はキャッシュを利用することでレスポンスを向上させる
    private func loadProductsIfNeeded() async {
        let alreadyLoaded = await MainActor.run { storeProducts.isEmpty == false }
        if alreadyLoaded {
            return
        }

        let identifiers = Set(AZUKI_CREDIT_PURCHASE_OPTIONS.map { $0.productId })
        do {
            let products = try await Product.products(for: identifiers)
            await MainActor.run {
                storeProducts = products
            }
        } catch {
            #if DEBUG
            print("failed to load products: \(error)")
            #endif
        }
    }

    /// キャッシュ済みまたは都度取得した `Product` を返す
    private func fetchProduct(matching productId: String) async throws -> Product {
        // すでに取得済みの `Product` があればそのまま返して無駄なネットワークアクセスを避ける
        let cachedProduct = await MainActor.run { storeProducts.first(where: { $0.id == productId }) }
        if let cached = cachedProduct {
            return cached
        }

        // StoreKit 2 の `Product.products` は例外を投げないため、`try` を使わずシンプルに取得する
        let fetched = try await Product.products(for: [productId])
        // 商品がまったく返ってこなければカタログの不整合と判断してエラーにする
        if fetched.isEmpty {
            throw PurchaseFlowError.productNotFound
        }
        // 目的のIDが見つからなければ同じく失敗として処理する
        guard let product = fetched.first(where: { $0.id == productId }) else {
            throw PurchaseFlowError.productNotFound
        }
        // 新しく取得した商品はキャッシュに積んで、次回以降は即座に返せるようにする
        await MainActor.run {
            storeProducts.append(product)
        }
        return product
    }

    /// StoreKit 2 の検証結果から信頼できる `Transaction` を取り出す
    private func resolveVerifiedTransaction(from result: VerificationResult<StoreKit.Transaction>) async throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(let transaction, let verificationError):
                let baseMessage = verificationError.localizedDescription
            // StoreKit 2 の `finish()` は iOS 18 から投げなくなったので、
            // ここでは失敗しても致命的ではないことを前提にベストエフォートで完了させる
            await transaction.finish()
            throw PurchaseFlowError.transactionUnverified(message: baseMessage)
        }
    }

    /// サーバーへレシート情報を転送し、残高を更新する
    private func registerPurchaseOnServer(option: (productId: String, priceYen: Int, credits: Int), transaction: StoreKit.Transaction) async throws -> AzukiApi.CreditPurchaseResult {
        let userId = await MainActor.run { creditStore.userId }
        let transactionId = String(transaction.id)
        let receipt = try await fetchAppStoreReceipt(from: transaction)
        return try await AzukiApi.shared.purchaseCredits(
            option: option,
            userId: userId,
            transactionId: transactionId,
            receiptData: receipt
        )
    }

    /// バンドル内に保存されたApp StoreレシートをBase64文字列として取得
    /// - Throws: レシートが存在しない、もしくは読み込みに失敗した場合は `PurchaseFlowError.receiptMissing`
    private func fetchAppStoreReceipt(from transaction: StoreKit.Transaction) async throws -> String {
        // iOS 18 以上をターゲットにしているが、StoreKit.Transaction 側の署名APIは
        // 利用環境のSDKに依存してビルドエラーとなるため、従来どおりバンドル内の
        // レシートファイルを読み出してBase64化する手順に戻す。
        // 今後 SDK 更新で `signedDataRepresentation` や類似APIが安定利用できたら、
        // そのタイミングでサーバーへの受け渡し形式を再検討する想定。

        // App Store レシートはバンドル内の決められた場所に配置されるため、
        // guard で存在確認しつつ、存在しない場合は課金情報を送信できないのでエラー扱いにする。
        // 引数の transaction は将来的に署名APIへ切り替える際に再活用するため、
        // 現段階では未使用であることを明示しておく。
        _ = transaction

        // iOS 18 からは `appStoreReceiptURL` が非推奨になったため、
        // セレクタ経由で取得してビルド時の警告を抑制する。
        // StoreKit 2 の新しい API が SDK に取り込まれ次第、
        // こちらの回避策は削除して `AppTransaction.shared` 系へ切り替える想定。
        let receiptURLSelector = NSSelectorFromString("appStoreReceiptURL")
        guard Bundle.main.responds(to: receiptURLSelector) else {
            throw PurchaseFlowError.receiptMissing
        }

        let receiptURLObject = Bundle.main.perform(receiptURLSelector)?.takeUnretainedValue()
        guard let receiptURL = receiptURLObject as? URL else {
            throw PurchaseFlowError.receiptMissing
        }

        // ファイル読み込み時に I/O エラーが発生する可能性があるため、
        // do-catch ではなく throws 付きの Data イニシャライザで自然にエラーを伝播させる。
        // 空データが返ったときもレシート欠落と同義なのでエラーに倒す。
        let receiptData = try Data(contentsOf: receiptURL)
        if receiptData.isEmpty {
            throw PurchaseFlowError.receiptMissing
        }

        // サーバー側は既存処理として Base64 の文字列表現を受け取るので、
        // Data -> Base64 -> String の順で変換し、空文字でないことを再チェックする。
        let base64String = receiptData.base64EncodedString()
        if base64String.isEmpty {
            throw PurchaseFlowError.receiptMissing
        }
        return base64String
    }

    /// トランザクションの完了とUI更新をまとめて処理する
    /// - Note: `finish()` は iOS 18 以降で `async` のみとなったため、例外ハンドリングは不要になった
    private func finalizePurchase(option: (productId: String, priceYen: Int, credits: Int), transaction: StoreKit.Transaction, serverResult: AzukiApi.CreditPurchaseResult) async {
        // 念のため完了処理を待ってからUIを更新することで、重複反映のリスクを避ける
        await transaction.finish()

        await MainActor.run {
            creditStore.overwrite(credits: serverResult.balance)
            alertState = .purchaseSuccess(added: serverResult.grantedCredits, priceYen: option.priceYen)
        }
    }

    /// StoreKit 2 の購入フローで想定されるエラー種別
    private enum PurchaseFlowError: LocalizedError {
        /// StoreKit 2 から商品情報が取得できなかった
        case productNotFound
        /// ネットワークやApp Store接続の問題で商品一覧が取得できなかった
        case productLoadFailed
        /// トランザクションが検証に失敗した（改ざんや未承認）
        case transactionUnverified(message: String)
        /// レシート情報が欠落または無効だった
        case receiptMissing
        var errorDescription: String? {
            switch self {
            case .productNotFound:
                return "対象の商品情報が見つかりませんでした。設定からリストを更新してください。"
            case .productLoadFailed:
                return "商品情報を取得できませんでした。ネットワーク環境をご確認のうえ再度お試しください。"
            case .transactionUnverified(let message):
                return message
            case .receiptMissing:
                return "購入情報の検証に必要なレシートが取得できませんでした。時間を置いて再試行してください。"
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

extension AiCreateView {
    /// 生成処理に必要なクレジットが十分にあるかを判定し、足りない場合のみサーバーへ問い合わせて再確認する
    /// - Parameter cost: 必要クレジット数
    /// - Returns: 利用可能ならtrue
    private func ensureSufficientCreditsForGeneration(cost: Int) async -> Bool {
        let hasEnoughLocally = await MainActor.run { cost <= creditStore.credits }
        if hasEnoughLocally {
            return true
        }
        await refreshCreditBalance()
        let refreshedCredits = await MainActor.run { creditStore.credits }
        return cost <= refreshedCredits
    }
}
