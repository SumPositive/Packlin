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
    /// TextEditorにフォーカスが当たっているかどうかを追跡するフォーカス状態
    @FocusState private var isRequirementFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                AiCreateView(requirementFocus: $isRequirementFocused)
            }
            // 背景タップでキーボードを閉じるためのジェスチャ
            .contentShape(Rectangle())
            // スクロール操作でフォーカスを外してキーボードを閉じる（タップだとTextEditorが含まれて面倒）
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onChanged { _ in
                    // ScrollView本体でのドラッグだけに反応し、TextEditor内の操作ではフォーカスを保つ
                    if isRequirementFocused {
                        isRequirementFocused = false
                    }
                },
                including: .gesture
            )
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
    @Environment(\.locale) private var locale
    @EnvironmentObject private var creditStore: CreditStore
    /// フォーカス制御を外部（親ビュー）から受け取るためのバインディング
    private let requirementFocus: FocusState<Bool>.Binding

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
    /// すでにユーザーへ通知済みのトランザクションIDを記録し、同じ購入結果のアラートを連続表示しないようにする
    @State private var notifiedTransactionIds: Set<String> = []

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 親ビューからフォーカス制御のバインディングを受け取るためのイニシャライザ
    /// - Parameter requirementFocus: TextEditorのフォーカスを外部で管理するためのバインディング
    init(requirementFocus: FocusState<Bool>.Binding) {
        self.requirementFocus = requirementFocus
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
            Text("下の欄に要望を入力して「チャッピー！作って」を押せば、チャッピーが要望に応じたパックを提案してくれます。それを修正して自由に使用することができます。提案されたパックの取り込みに成功するとAI利用券が1枚減ります")
                .font(.body)
                .foregroundStyle(.secondary)
            
            // 入力欄とプレースホルダー
            ZStack(alignment: .topLeading) {
                // 入力欄
                TextEditor(text: $requirementText)
                    .frame(height: 200)
                    .padding(8)
                    // TextEditorにフォーカスを割り当て、親からの制御を受ける
                    .focused(requirementFocus)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel(Text("パックの要望入力"))

                // プレースホルダー
                if isRequirementEmpty {
                    // 入力例
                    Text("""
                        （例）
                        海外旅行5泊6日　イギリス、スペイン
                        家族4人（大人2人、子ども2人）
                        ＜日程、行程、アクティビティなども記入＞
                        4人でスキューバダイビングに参加
                        雨天も想定。救急用品も持参
                        """)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false) // タップを奪わないようにヒットテストを無効化
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
                    Text(isGenerating ? "作ってます..." : "チャッピー！作って")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isRequirementEmpty || isGenerating)

            if isGenerating {
                Text("チャッピーが作ってます。もう少しお待ちください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            //Divider() // 区切り線
            
            HStack {
                Spacer()
                Text("AI利用券残り \(creditStore.credits) 枚")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // AI利用券購入
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
            // 一連の購入処理で通知済みリストに溜めたIDも破棄しておき、再表示時に最新状態で判断できるようにする
            notifiedTransactionIds.removeAll()
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
            alertState = .generationFailure(message: String(localized: "パック作成の要望を入れてね"))
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

                        GALogger.log(.packlin_request(userId: userId,
                                                      requirement: trimmedRequirement))
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
                    ?? String(localized: "認証に失敗しました。アプリを再起動して再度お試しください")
                    await MainActor.run {
                        alertState = .generationFailure(message: message)
                    }
                default:
                    let message = apiError.errorDescription
                    ?? String(localized: "チャッピーが忙しそうです。時間をおいて再度お試しください")
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
                                                        String(localized: "チャッピーが忙しそうです。時間をおいて再度お試しください"))
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
            // 日本と海外で商品IDが分かれたため、両方のトランザクションを順番に確認する
            for productId in option.allProductIds {
                if Task.isCancelled {
                    break
                }
                guard let latest = await Transaction.latest(for: productId) else {
                    continue
                }
                didAttemptVerification = true
                do {
                    let (transaction, storekitJws) = try await resolveVerifiedTransaction(from: latest)
                    let receiptData = transaction.jsonRepresentation
                    let receipt = receiptData.base64EncodedString()
                    let verification = try await AzukiApi.shared.verifyPurchase(
                        userId: userId,
                        productId: productId,
                        transactionId: String(transaction.id),
                        receipt: receipt,
                        storekitJws: storekitJws,
                        grantCredits: option.tickets
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
                ?? String(localized: "AI利用券の枚数が確認できません。時間をおいて再度お試しください。")
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
                    alertState = .generationFailure(message: String(localized: "AI利用券の枚数が確認できません。通信環境をご確認ください。"))
                }
            }
            #if DEBUG
            print("[AzukiApi] unexpected error while refreshing balance: \(error)")
            #endif
        }
    }

    /// AI利用回数券購入
    /// - Parameter option: Configで定義した購入オプション構造体
    private func purchaseCredits(option: AzukiCreditPurchaseOption) {
        // Localeから現在のストア商品IDを導出しておき、Task内で安全に利用する
        let currentLocale = locale
        let productId = option.productId(for: currentLocale)
        Task {
            // 端末に保管できる上限を超えないか事前にチェックする
            let limit = AZUKI_CREDIT_BALANCE_LIMIT
            let currentCredits = await MainActor.run { creditStore.credits }
            if limit <= currentCredits || limit < currentCredits + option.tickets {
                await MainActor.run {
                    alertState = .purchaseLimitReached(max: limit)
                    processingProductId = nil
                }
                return
            }

            await MainActor.run {
                // 複数ボタンが並ぶため、購入中の選択肢のみローディング表示へ切り替える
                processingProductId = productId
            }

            let msgPurchaseCancel = String(localized: "購入を中止しました。課金されません。再度お試しください。")
            
            do {
                // 実機（Sandbox Apple ID）での挙動確認を前提とし、StoreKit 本番フローをそのまま利用する
                // シミュレータ用のテストセッションはあえて起動せず、実運用と同じ購入体験を得る
                // 1. StoreKit2 から商品情報を取得（初回のみネットワーク越し）
                await loadProductsIfNeeded()
                let product = try await fetchProduct(matching: productId)

                // 2. ユーザーに課金ダイアログを提示
                let outcome = try await product.purchase()

                switch outcome {
                    case .success(let verificationResult):
                        // 3. トランザクション署名を検証し、正規購入であればサーバーへ伝えて残高を加算する
                        let (transaction, storekitJws) = try await resolveVerifiedTransaction(from: verificationResult)
                        await finalizePurchase(option: option, productId: productId, transaction: transaction, storekitJws: storekitJws)
                        
                    case .pending:
                        // ファミリー共有などで承認待ちになる場合
                        await MainActor.run {
                            alertState = .purchaseFailure(message: String(localized: "購入の承認待ちです。まだ課金はされません。承認が完了すると自動で反映されます。"))
                        }
                        
                    case .userCancelled:
                        // ユーザーがキャンセルした場合は状況を伝えるメッセージを表示
                        await MainActor.run {
                            alertState = .purchaseFailure(message: msgPurchaseCancel)
                        }
                        
                    @unknown default:
                        await MainActor.run {
                            alertState = .purchaseFailure(message: String(localized: "想定外の購入結果が返りました。時間をおいて再度お試しください。"))
                        }
                }
            } catch let flowError as PurchaseFlowError {
                await MainActor.run {
                    let message = flowError.errorDescription
                        ?? String(localized: "AI利用券の購入に失敗しました。")
                    alertState = .purchaseFailure(message: message)
                }
            } catch StoreKitError.userCancelled {
                await MainActor.run {
                    // StoreKitが返すユーザーキャンセルはここで一元的に処理し、二重アラートの発生を確実に抑止する
                    alertState = .purchaseFailure(message: msgPurchaseCancel)
                }
            } catch let storekitError as StoreKitError {
                await MainActor.run {
                    // StoreKit起因のエラーは極力詳細情報を提示し、ユーザーが状況を把握しやすいよう努める
                    let message = storekitError.errorDescription
                        ?? storekitError.localizedDescription
                    alertState = .purchaseFailure(message: message)
                }
            } catch is CancellationError {
                await MainActor.run {
                    // Taskキャンセル（StoreKit購入ダイアログを閉じる等）もユーザーによる中断として扱い、二重アラートを避ける
                    alertState = .purchaseFailure(message: msgPurchaseCancel)
                }
            } catch let localized as LocalizedError {
                await MainActor.run {
                    let message = localized.errorDescription ?? localized.localizedDescription
                    alertState = .purchaseFailure(message: message)
                }
            } catch {
                await MainActor.run {
                    alertState = .purchaseFailure(message: String(localized: "AI利用券の購入中にエラーが発生しました。通信環境をご確認ください。"))
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
                Text("AI利用券の購入")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "cart")
                    .symbolRenderingMode(.hierarchical)
            }

            // Config側で定義した金額・クレジットの対応表をそのまま描画する
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AZUKI_CREDIT_PURCHASE_OPTIONS, id: \.productIdJapan) { option in
                    Button {
                        purchaseCredits(option: option)
                    } label: {
                        HStack(spacing: 0) {
                            if processingProductId == option.productId(for: locale) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .padding(.horizontal, 8)
                            }
                            Text(option.localizedButtonTitle(for: locale))
                                .font(.title3.weight(.bold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor.opacity(1.0))
                    .disabled(processingProductId != nil || isPurchaseUnavailable(for: option))
                }
            }
            .padding(.horizontal, 40)

            if let warningMessage = purchaseLimitWarning {
                Text(warningMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            }

            Label {
                Text("AI利用券は端末に安全に保管されますが、端末が壊れたりアプリを削除すると失われます。貯めずに早めにお使いください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    //.imageScale(.large)
                    .foregroundColor(.red) 
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    /// 購入オプションが上限に達して利用できないかどうかを判定する
    private func isPurchaseUnavailable(for option: AzukiCreditPurchaseOption) -> Bool {
        // 画面表示中はMainActor上なので直接残高を参照してよい
        let limit = AZUKI_CREDIT_BALANCE_LIMIT
        let currentCredits = creditStore.credits
        if limit <= currentCredits {
            return true
        }
        return limit < currentCredits + option.tickets
    }

    /// 現在の残高と上限に応じて注意書きを表示するための文言を返す
    private var purchaseLimitWarning: String? {
        let limit = AZUKI_CREDIT_BALANCE_LIMIT
        let currentCredits = creditStore.credits
        if limit <= currentCredits {
            return String(localized: "AI利用券は最大\(limit)枚まで保管できます。今ある券を利用してからご購入ください。")
        }
        let remainingCapacity = limit - currentCredits
        let hasDisabledOption = AZUKI_CREDIT_PURCHASE_OPTIONS.contains { option in
            limit < currentCredits + option.tickets
        }
        if hasDisabledOption {
            return String(localized: "あと\(remainingCapacity)枚まで購入できます。上限を超える購入はできません。")
        }
        return nil
    }

    /// StoreKit 2 から商品情報を取得し、`storeProducts` へキャッシュする
    /// - Note: 初期表示時にまとめて取得し、以降はキャッシュを利用することでレスポンスを向上させる
    private func loadProductsIfNeeded() async {
        let alreadyLoaded = await MainActor.run { storeProducts.isEmpty == false }
        if alreadyLoaded {
            return
        }

        // StoreKit の商品取得も実機 Sandbox を前提にしているため、シミュレータ固有の処理は挟まない
        let currentLocale = locale
        let identifiers = Set(AZUKI_CREDIT_PURCHASE_OPTIONS.map { $0.productId(for: currentLocale) })
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
                // iOS 18 では signedData が Base64 文字列の Data として返る場合もあるため、拡張プロパティ側で安全に復元する
                let jws = result.jwsRepresentation  // StoreKit 2
                //print("dotCount =", jws.filter { $0 == "." }.count)   // => 2 のはず
                //print("firstDot at", jws.firstIndex(of: ".") != nil)  // true
                //print("length =", jws.count)
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
    private func finalizePurchase(option: AzukiCreditPurchaseOption,
                                  productId: String,
                                  transaction: StoreKit.Transaction,
                                  storekitJws: String) async {
        // 0. 同じトランザクションに対して複数回アラートを出さないよう、IDをキーに管理する
        let transactionIdentifier = String(transaction.id)

        // 1. StoreKitトランザクションの完了はサーバー検証の成功を確認してから行い、
        //    検証に失敗したケースではfinishを呼ばずに中断できるようにする

        // 2. サーバーへ送信するためのユーザーIDやレシートデータをMainActorから取り出す
        let userId = await MainActor.run { creditStore.userId }
        let transactionId = transactionIdentifier
        // StoreKitのトランザクションはJSON Dataとして取得し、Base64で安全に送信する
        let receiptData = transaction.jsonRepresentation
        let receipt = receiptData.base64EncodedString()
        // StoreKit 2 が提供するJWS文字列も同時に送り、サーバーで署名検証してもらう
        // Swift 5 + iOS 18 以降で追加された signedData と従来の jwsRepresentation を状況に応じて切り替え済み
        
        // verifyPurchaseに失敗し、購入中止したときのメッセージ
        let fallbackMessage = String(
            localized: "購入の結果待ちです。まだ課金はされません。確認が完了すると自動で反映されます。")


        do {
            // 3. azuki-apiへ購入内容を通知し、サーバー側でも残高を更新してもらう
            let verification = try await AzukiApi.shared.verifyPurchase(
                userId: userId,
                productId: productId,
                transactionId: transactionId,
                receipt: receipt,
                storekitJws: storekitJws,
                grantCredits: option.tickets
            )
            await MainActor.run {
                // 4. サーバーが返した残高でKeychainを上書きし、UIへ成功メッセージを表示
                creditStore.overwrite(credits: verification.balance)
                if notifiedTransactionIds.contains(transactionIdentifier) == false {
                    // ユーザーへはまだ案内していない購入なので、このタイミングでアラートを掲示する
                    notifiedTransactionIds.insert(transactionIdentifier)
                    if verification.duplicate {
                        alertState = .purchaseAlreadyProcessed
                    } else {
                        alertState = .purchaseSuccess(added: option.tickets, productId: productId)
                    }
                }
            }
            // 5. サーバー検証まで完了したため、ここで初めてStoreKit側のトランザクションを終了させる
            await transaction.finish() // 購入完了
            
        } catch let apiError as AzukiAPIError {
            // サーバー側ですでに処理済みであれば最新残高を取得し直す
            if case .duplicateTransaction = apiError {
                await refreshCreditBalanceFromServer(showAlertOnFailure: false)
                await MainActor.run {
                    if notifiedTransactionIds.contains(transactionIdentifier) == false {
                        // サーバー側で既に処理済みだった購入についても、一度だけ状況を知らせる
                        notifiedTransactionIds.insert(transactionIdentifier)
                        alertState = .purchaseAlreadyProcessed
                    }
                }
                // duplicate もサーバー連携が成立しているため、確実にトランザクションを消化する
                await transaction.finish() // 購入完了
                return
            }
            await MainActor.run {
                // サーバー検証で失敗した場合はトランザクションを完了させず、ユーザーにも購入を中止した旨を案内する
                let detailed = apiError.errorDescription ?? "verifyPurchase.error"
                alertState = .purchaseFailure(message: fallbackMessage + "\n\n" + detailed)
            }
            return
        } catch {
            await MainActor.run {
                // 不明なエラーでもトランザクションを消化しないことで、後から再処理できるようにする
                alertState = .purchaseFailure(message: fallbackMessage)
            }
            return
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
            guard let option = AZUKI_CREDIT_PURCHASE_OPTIONS.first(where: { $0.contains(productId: transaction.productID) }) else {
                await transaction.finish()
                return
            }

            await finalizePurchase(option: option,
                                   productId: transaction.productID,
                                   transaction: transaction,
                                   storekitJws: storekitJws)
        } catch {
            // 検証に失敗した場合やAPI通信の例外は、デバッグ出力のみ行いユーザーへ重複通知しない
            log(.debug, "[Transaction] failed to handle update: \(error)")
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
                return String(localized: "商品情報が見つかりません。")
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
        case purchaseSuccess(added: Int, productId: String)
        /// サーバー側ですでに反映済みの購入だった場合
        case purchaseAlreadyProcessed
        /// クレジット購入が失敗した場合
        case purchaseFailure(message: String)
        /// クレジット保管上限に達している場合
        case purchaseLimitReached(max: Int)

        var id: String {
            switch self {
            case .generationSuccess(let packName):
                return "ai-generationSuccess-\(packName)"
            case .generationFailure(let message):
                return "ai-generationFailure-\(message)"
            case .creditShortage:
                return "ai-creditShortage"
            case .purchaseSuccess(let added, let productId):
                return "ai-purchaseSuccess-\(added)-\(productId)"
            case .purchaseAlreadyProcessed:
                return "ai-purchaseAlreadyProcessed"
            case .purchaseFailure(let message):
                return "ai-purchaseFailure-\(message)"
            case .purchaseLimitReached(let max):
                return "ai-purchaseLimitReached-\(max)"
            }
        }

        var title: String {
            switch self {
            case .generationSuccess:
                return String(localized: "パックが出来上がりました")
            case .generationFailure:
                return String(localized: "パックを生成できません")
            case .creditShortage:
                return String(localized: "AI利用券が不足しています")
            case .purchaseSuccess:
                return String(localized: "購入が完了しました")
            case .purchaseAlreadyProcessed:
                return String(localized: "購入履歴が確認できました")
            case .purchaseFailure:
                return String(localized: "購入状況")
            case .purchaseLimitReached:
                return String(localized: "これ以上追加購入できません")
            }
        }

        var message: String {
            switch self {
            case .generationSuccess(let packName):
                return String(localized: "パック一覧に『\(packName)』を追加しました。パック一覧に戻って見てください")
            case .generationFailure(let message):
                return message
            case .creditShortage:
                return String(localized: "AI利用券が不足しています。下のメニューから購入してください")
            case .purchaseSuccess(let added, _):
                return String(localized: "AI利用券を\(added)枚追加しました。")
            case .purchaseAlreadyProcessed:
                return String(localized: "この購入はすでに完了しています。枚数を更新しました。")
            case .purchaseFailure(let message):
                return message
            case .purchaseLimitReached(let max):
                return String(localized: "AI利用券は最大\(max)枚まで保管できます。既存の券を利用してから再度お試しください。")
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
            // iOS 18 以降では signedData から直接 JWS 文字列が取得できる場合と、Base64 文字列の Data が返る場合がある
            // そのためまずは UTF-8 文字列へ復元を試み、ピリオドが含まれて正常なJWS形式であればそのまま返す
//            if let directString = String(data: self.signedData, encoding: .utf8), directString.contains(".") {
//                return directString
//            }
            // directString が取得できない場合は Base64 デコードを試し、復号後に UTF-8 文字列化してサーバーへ送る
            if let decodedData = Data(base64Encoded: self.signedData),
               let decodedString = String(data: decodedData, encoding: .utf8),
               decodedString.contains(".") {
                return decodedString
            }
        }
        // iOS 15 〜 17 では従来の文字列プロパティをそのまま返し、既存のサーバー検証フローを継続させる
        // ここまででどちらの変換も失敗した場合も旧来プロパティへフォールバックする
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
