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
                    Button(String(localized: "閉じる")) {
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
    /// 初回表示時にサーバー残高とKeychain残高を同期したかどうかのフラグ
    @State private var didRequestInitialBalance = false
    /// StoreKitのトランザクション更新ストリームを監視するためのタスク
    @State private var transactionObservationTask: Task<Void, Never>?

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // セクションタイトル
            Label {
                Text("チャッピー(AI)にパックを作ってもらおう")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }

            // 操作説明（アプリ内生成の流れを簡潔に案内）
            Text("要望を入力して「チャッピーに作ってもらう」を押してください。新しいパックの作成に成功するとAI利用回数が1つ減ります")
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
                    .accessibilityLabel(Text("PackListの要件入力"))

                if isRequirementEmpty {
                    // 入力例
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
                    Text(isGenerating ? "お作りしています..." : "チャッピーに作ってもらう")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isRequirementEmpty || isGenerating)

            if isGenerating {
                Text("チャッピーに依頼中です。もう少しお待ちください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider() // 区切り線
            
            Text("AI利用回数残り \(creditStore.credits) 回")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            

            // AI利用回数券購入
            creditPurchaseMenu
            
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // AzukiApiへトークン復旧ロジックを注入しておくことで、Keychainが空でも即座に復旧できるようにする
            await AzukiApi.shared.registerTokenRecoveryHandler {
                await recoverAccessTokenByVerifyingLatestTransactions()
            }
            // 初回表示時に商品情報を取得しつつ、サーバー残高との同期も直ちに行う
            await loadProductsIfNeeded()
            // サーバー残高との同期は一度だけ実行し、Keychainの値と揃えておく
            await syncCreditBalanceIfNeeded()
            // 購入完了後にViewがフォアグラウンドでなくても反映できるよう、トランザクション更新を監視する
            if transactionObservationTask == nil {
                transactionObservationTask = Task {
                    await observeTransactionUpdates()
                }
            }
        }
        .onDisappear {
            // ビューを離れる際には監視タスクを終了し、重複起動を避ける
            transactionObservationTask?.cancel()
            transactionObservationTask = nil
            // ビューが消えた後は復旧ハンドラを解除し、不要な保持を避ける
            Task {
                await AzukiApi.shared.clearTokenRecoveryHandler()
            }
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

    /// azuki-api経由でOpenAIにパック生成を依頼する
    private func generatePackWithOpenAI() {
        let trimmedRequirement = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRequirement.isEmpty {
            alertState = .generationFailure(message: String(localized: "ご要望を入れてください。"))
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

            // ローカル残高が不足している場合に限り不足アラートを出す（Keychain保存なので通信不要）
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
                let dto = try await requestPackFromServer(
                    userId: userId,
                    requirement: trimmedRequirement,
                    canAttemptRecovery: true
                )
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
                switch apiError {
                case .insufficientCredits:
                    // サーバー側で不足判定となったのでローカルを戻さず、Keychain残高を最新状態で使い続ける
                    shouldRestoreCredits = false
                    // サーバーの残高を参照してKeychainを最新化し、複数端末での消費にも追随させる
                    await refreshCreditBalanceFromServer(showAlertOnFailure: false)
                    await MainActor.run {
                        alertState = .creditShortage
                    }
                case .unauthorized, .forbiddenUser, .missingAuthToken, .tokenExpired:
                    let message = apiError.errorDescription
                    ?? String(localized: "認証に失敗しました。アプリを再起動しても解決しない場合はサポートへお問い合わせください。")
                    await MainActor.run {
                        alertState = .generationFailure(message: message)
                    }
                default:
                    let message = apiError.errorDescription
                    ?? String(localized: "チャッピーが忙しいようです。時間をおいて再度お試しください")
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
                    alertState = .generationFailure(message:
                                                        String(localized: "チャッピーが忙しいようです。時間をおいて再度お試しください"))
                }
            }
        }
    }

    /// OpenAI経由の生成リクエストを実行し、必要に応じてトークン再取得を挟む
    /// - Parameters:
    ///   - userId: サーバー側でクレジット消費対象となるユーザーID
    ///   - requirement: ユーザーが入力した要件
    ///   - canAttemptRecovery: トークン再取得を試行できるかどうか（再帰呼び出し抑制用）
    /// - Returns: サーバーが返したPack生成結果DTO
    private func requestPackFromServer(userId: String, requirement: String, canAttemptRecovery: Bool) async throws -> PackJsonDTO {
        do {
            return try await AzukiApi.shared.generatePack(userId: userId, requirement: requirement)
        } catch let apiError as AzukiAPIError {
            if canAttemptRecovery && shouldAttemptTokenRecovery(for: apiError) {
                let recovered = await recoverAccessTokenByVerifyingLatestTransactions()
                if recovered {
                    return try await requestPackFromServer(
                        userId: userId,
                        requirement: requirement,
                        canAttemptRecovery: false
                    )
                }
            }
            throw apiError
        }
    }

    /// 指定したエラーに対してトークン復旧処理を挟むべきか判定する
    /// - Parameter error: azuki-apiから受け取ったエラー
    /// - Returns: トークン復旧が必要ならtrue
    private func shouldAttemptTokenRecovery(for error: AzukiAPIError) -> Bool {
        switch error {
        case .missingAuthToken, .unauthorized, .tokenExpired:
            return true
        default:
            return false
        }
    }

    /// 最新の購入トランザクションを再検証してアクセストークンを取り直す
    /// - Returns: 新しいトークンが取得できたと推定できる場合はtrue
    @discardableResult
    private func recoverAccessTokenByVerifyingLatestTransactions() async -> Bool {
        // StoreKit履歴から直近の購入をサーバーへ再通知し、トークンの再払い出しを期待する
        let userId = await MainActor.run { creditStore.userId }
        var didAttemptVerification = false
        var didRecoverToken = false

        for option in AZUKI_CREDIT_PURCHASE_OPTIONS {
            if Task.isCancelled {
                break
            }
            guard let latest = await Transaction.latest(for: option.productId) else {
                continue
            }
            didAttemptVerification = true
            do {
                let (transaction, storekitJws) = try await resolveVerifiedTransaction(from: latest)
                let receiptData = transaction.jsonRepresentation
                let receipt = receiptData.base64EncodedString()
                let verification = try await AzukiApi.shared.verifyPurchase(
                    userId: userId,
                    productId: option.productId,
                    transactionId: String(transaction.id),
                    receipt: receipt,
                    storekitJws: storekitJws,
                    grantCredits: option.credits
                )
                await MainActor.run {
                    // サーバー側が返した最新残高でKeychainを更新し、UIと整合させる
                    creditStore.overwrite(credits: verification.balance)
                }
                didRecoverToken = true
            } catch let apiError as AzukiAPIError {
                if case .duplicateTransaction = apiError {
                    // すでに処理済みなら残高だけ再取得しておき、トークンはサーバー任せとする
                    await refreshCreditBalanceFromServer(showAlertOnFailure: false)
                    didRecoverToken = true
                }
            } catch {
                // 個別のトランザクションで失敗しても他の履歴から再取得を続ける
                continue
            }
        }

        if didRecoverToken {
            return true
        }
        if didAttemptVerification == false {
            return false
        }
        return false
    }

    /// Keychainに保持している残高とサーバーの残高を初回表示時に同期する
    private func syncCreditBalanceIfNeeded() async {
        let shouldFetch = await MainActor.run { () -> Bool in
            if didRequestInitialBalance {
                // すでに同期済みであれば追加のサーバーアクセスは避ける
                return false
            }
            didRequestInitialBalance = true
            return true
        }
        if shouldFetch == false {
            return
        }
        await refreshCreditBalanceFromServer(showAlertOnFailure: false)
    }

    /// サーバーに保存されている残高を取得してKeychainへ反映する
    /// - Parameter showAlertOnFailure: 失敗時にユーザーへアラート表示するかどうか
    private func refreshCreditBalanceFromServer(showAlertOnFailure: Bool) async {
        let userId = await MainActor.run { creditStore.userId }
        do {
            // azuki-apiへ問い合わせて最新残高を受け取り、Keychainに保持している値と揃える
            let remoteBalance = try await AzukiApi.shared.fetchCreditBalance(userId: userId)
            await MainActor.run {
                creditStore.overwrite(credits: remoteBalance)
            }
        } catch let apiError as AzukiAPIError {
            if showAlertOnFailure {
                let message = apiError.errorDescription
                ?? String(localized: "サーバーの残高確認に失敗しました。時間をおいて再度お試しください。")
                await MainActor.run {
                    alertState = .generationFailure(message: message)
                }
            }
            #if DEBUG
            print("[AzukiApi] failed to refresh balance: \(apiError)")
            #endif
        } catch {
            if showAlertOnFailure {
                await MainActor.run {
                    alertState = .generationFailure(message: String(localized: "サーバーの残高確認に失敗しました。通信環境をご確認ください。"))
                }
            }
            #if DEBUG
            print("[AzukiApi] unexpected error while refreshing balance: \(error)")
            #endif
        }
    }

    /// AI利用回数券購入
    /// - Parameter option: Configで定義したオプションタプル
    private func purchaseCredits(option: (productId: String, priceYen: Int, credits: Int)) {
        Task {
            await MainActor.run {
                // 複数ボタンが並ぶため、購入中の選択肢のみローディング表示へ切り替える
                processingProductId = option.productId
            }

            do {
                // 実機（Sandbox Apple ID）での挙動確認を前提とし、StoreKit 本番フローをそのまま利用する
                // シミュレータ用のテストセッションはあえて起動せず、実運用と同じ購入体験を得る
                // 1. StoreKit2 から商品情報を取得（初回のみネットワーク越し）
                await loadProductsIfNeeded()
                let product = try await fetchProduct(matching: option.productId)

                // 2. ユーザーに課金ダイアログを提示
                let outcome = try await product.purchase()

                switch outcome {
                case .success(let verificationResult):
                    // 3. トランザクション署名を検証し、正規購入であればサーバーへ伝えて残高を加算する
                    let (transaction, storekitJws) = try await resolveVerifiedTransaction(from: verificationResult)
                    await finalizePurchase(option: option, transaction: transaction, storekitJws: storekitJws)

                case .pending:
                    // ファミリー共有などで承認待ちになる場合
                    await MainActor.run {
                        alertState = .purchaseFailure(message: String(localized: "購入が承認待ちです。承認が完了すると自動で反映されます。"))
                    }

                case .userCancelled:
                    // ユーザーがキャンセルした場合は状況を伝えるメッセージを表示
                    await MainActor.run {
                        alertState = .purchaseFailure(message: String(localized: "購入をキャンセルしました。必要であれば再度お試しください。"))
                    }

                @unknown default:
                    await MainActor.run {
                        alertState = .purchaseFailure(message: String(localized: "想定外の購入結果が返りました。時間をおいて再度お試しください。"))
                    }
                }
            } catch let flowError as PurchaseFlowError {
                await MainActor.run {
                    let message = flowError.errorDescription
                        ?? String(localized: "AI利用回数券の購入に失敗しました。")
                    alertState = .purchaseFailure(message: message)
                }
            } catch let localized as LocalizedError {
                await MainActor.run {
                    let message = localized.errorDescription ?? localized.localizedDescription
                    alertState = .purchaseFailure(message: message)
                }
            } catch {
                await MainActor.run {
                    alertState = .purchaseFailure(message: String(localized: "AI利用回数券の購入中にエラーが発生しました。通信環境をご確認ください。"))
                }
            }

            await MainActor.run {
                processingProductId = nil
            }
        }
    }

    /// AI利用回数券購入メニュー
    private var creditPurchaseMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("AI利用回数券購入")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "cart")
                    .symbolRenderingMode(.hierarchical)
            }

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
                            Text("\(option.credits)回券：¥\(option.priceYen)")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor.opacity(0.8))
                    .disabled(processingProductId != nil)
                }
            }
            .padding(.horizontal, 32)
            
            Label {
                Text("回数券は端末のKeychainとサーバーの両方に安全に保管されます。同じユーザーであれば再インストール後も自動で復元されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
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

        // StoreKit の商品取得も実機 Sandbox を前提にしているため、シミュレータ固有の処理は挟まない
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

        // 実運用と同じく App Store 経由で取得するので、追加のテストセッション初期化などは行わない
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
    private func resolveVerifiedTransaction(from result: VerificationResult<StoreKit.Transaction>) async throws -> (transaction: StoreKit.Transaction, storekitJws: String) {
        switch result {
        case .verified(let transaction):
            // signedData と jwsRepresentation を自動で出し分けたJWS文字列を同時に返し、呼び出し側での煩雑な分岐を避ける
                let jws = result.jwsRepresentation //.jwsForServer
            return (transaction, jws)
        case .unverified(let transaction, let verificationError):
            let baseMessage = verificationError.localizedDescription
            // StoreKit 2 の `finish()` は iOS 18 から投げなくなったので、
            // ここでは失敗しても致命的ではないことを前提にベストエフォートで完了させる
            await transaction.finish()
            throw PurchaseFlowError.transactionUnverified(message: baseMessage)
        }
    }

    /// トランザクションの完了とKeychain残高・サーバー残高の更新をまとめて処理する
    private func finalizePurchase(option: (productId: String, priceYen: Int, credits: Int), transaction: StoreKit.Transaction, storekitJws: String) async {
        // 1. StoreKitのトランザクション完了はdeferでまとめて実行し、途中で失敗してもダブルカウントを避ける
        defer {
            Task {
                await transaction.finish()
            }
        }

        // 2. サーバーへ送信するためのユーザーIDやレシートデータをMainActorから取り出す
        let userId = await MainActor.run { creditStore.userId }
        let transactionId = String(transaction.id)
        // StoreKitのトランザクションはJSON Dataとして取得し、Base64で安全に送信する
        let receiptData = transaction.jsonRepresentation
        let receipt = receiptData.base64EncodedString()
        // StoreKit 2 が提供するJWS文字列も同時に送り、サーバーで署名検証してもらう
        // Swift 5 + iOS 18 以降で追加された signedData と従来の jwsRepresentation を状況に応じて切り替え済み

        do {
            // 3. azuki-apiへ購入内容を通知し、サーバー側でも残高を更新してもらう
            let verification = try await AzukiApi.shared.verifyPurchase(
                userId: userId,
                productId: option.productId,
                transactionId: transactionId,
                receipt: receipt,
                storekitJws: storekitJws,
                grantCredits: option.credits
            )
            await MainActor.run {
                // 4. サーバーが返した残高でKeychainを上書きし、UIへ成功メッセージを表示
                creditStore.overwrite(credits: verification.balance)
                if verification.duplicate {
                    alertState = .purchaseAlreadyProcessed
                } else {
                    alertState = .purchaseSuccess(added: option.credits, priceYen: option.priceYen)
                }
            }
        } catch let apiError as AzukiAPIError {
            // サーバー側ですでに処理済みであれば最新残高を取得し直す
            if case .duplicateTransaction = apiError {
                await refreshCreditBalanceFromServer(showAlertOnFailure: false)
                await MainActor.run {
                    alertState = .purchaseAlreadyProcessed
                }
                return
            }
            let message = apiError.errorDescription
            ?? String(localized: "購入情報の確認に失敗しました。時間をおいて再度お試しください。")
            await MainActor.run {
                alertState = .purchaseFailure(message: message)
            }
        } catch {
            await MainActor.run {
                alertState = .purchaseFailure(message: String(localized: "AI利用回数券の購入結果をサーバーへ反映できませんでした。通信環境をご確認ください。"))
            }
        }
    }

    /// StoreKitのトランザクション更新ストリームを処理し、取りこぼしなくサーバー連携する
    private func observeTransactionUpdates() async {
        // Viewが表示されている間は常に監視を続け、キャンセルされたらループを抜ける
        for await update in Transaction.updates {
            if Task.isCancelled {
                break
            }

            await handleTransactionUpdate(update)
        }
    }

    /// トランザクション更新の1件を検証・反映する
    /// - Parameter update: StoreKitから届く検証結果付きトランザクション
    private func handleTransactionUpdate(_ update: VerificationResult<StoreKit.Transaction>) async {
        do {
            // StoreKitの検証結果を通過したトランザクションのみを対象にする
            let (transaction, storekitJws) = try await resolveVerifiedTransaction(from: update)
            // Configに存在しないProduct IDの場合は終了処理だけ行い、以降の処理を避ける
            guard let option = AZUKI_CREDIT_PURCHASE_OPTIONS.first(where: { $0.productId == transaction.productID }) else {
                await transaction.finish()
                return
            }

            await finalizePurchase(option: option, transaction: transaction, storekitJws: storekitJws)
        } catch {
            // 検証に失敗した場合やAPI通信の例外は、デバッグ出力のみ行いユーザーへ重複通知しない
            #if DEBUG
            print("[Transaction] failed to handle update: \(error)")
            #endif
        }
    }

    /// StoreKit 2 の購入フローで想定されるエラー種別
    private enum PurchaseFlowError: LocalizedError {
        /// StoreKit 2 から商品情報が取得できなかった
        case productNotFound
        /// トランザクションが検証に失敗した（改ざんや未承認）
        case transactionUnverified(message: String)
        var errorDescription: String? {
            switch self {
            case .productNotFound:
                return String(localized: "対象の商品情報が見つかりませんでした。設定からリストを更新してください。")
            case .transactionUnverified(let message):
                return message
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
        /// サーバー側ですでに反映済みの購入だった場合
        case purchaseAlreadyProcessed
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
            case .purchaseAlreadyProcessed:
                return "ai-purchase-duplicate"
            case .purchaseFailure(let message):
                return "ai-purchase-failure-\(message)"
            }
        }

        var title: String {
            switch self {
            case .generationSuccess:
                return String(localized: "生成完了")
            case .generationFailure:
                return String(localized: "生成に失敗しました")
            case .creditShortage:
                return String(localized: "AI利用券不足")
            case .purchaseSuccess:
                return String(localized: "購入完了")
            case .purchaseAlreadyProcessed:
                return String(localized: "購入履歴を確認しました")
            case .purchaseFailure:
                return String(localized: "購入失敗")
            }
        }

        var message: String {
            switch self {
            case .generationSuccess(let packName):
                return String(localized: "パック『\(packName)』を追加しました。")
            case .generationFailure(let message):
                return message
            case .creditShortage:
                return String(localized: "AI利用券が不足しています。下の購入メニューから購入してください")
            case .purchaseSuccess(let added, let priceYen):
                return String(localized: "¥\(priceYen)の購入でAI利用券を\(added)追加しました。")
            case .purchaseAlreadyProcessed:
                return String(localized: "この購入はすでにサーバーへ登録済みでした。最新残高を読み込み済みです。")
            case .purchaseFailure(let message):
                return message
            }
        }
    }
}

// MARK: - StoreKit 2 互換ヘルパー

@available(iOS 15.0, *)
private extension VerificationResult where SignedType == StoreKit.Transaction {
    /// サーバー検証に送るJWS（文字列）。iOS 18 以降で追加された `signedData` と旧来の `jwsRepresentation` を透過的に扱う。
    /// - Note: Swift 5 かつ iOS 18 以降であれば `signedData` が Data として提供されるのでUTF-8文字列へ変換し、それ未満では既存プロパティを利用する。
    var jwsForServer: String {
        if #available(iOS 18.0, *) {
            // iOS 18 以降では JWS Compact Serialization の Data が返るため、UTF-8 文字列へ復元して返却する
            if let string = String(data: self.signedData, encoding: .utf8) {
                return string
            }
        }
        // iOS 15 〜 17 では従来の文字列プロパティをそのまま返し、既存のサーバー検証フローを継続させる
        return self.jwsRepresentation
    }
}

extension AiCreateView {
    /// 生成処理に必要なクレジットが十分にあるかを判定し、Keychain保存の残高だけで安全に判断する
    /// - Parameter cost: 必要クレジット数
    /// - Returns: 利用可能ならtrue
    private func ensureSufficientCreditsForGeneration(cost: Int) async -> Bool {
        // MainActor上のCreditStoreから現在の残高を安全に読み取り、必要数と比較する
        let currentCredits = await MainActor.run { creditStore.credits }
        return cost <= currentCredits
    }
}
