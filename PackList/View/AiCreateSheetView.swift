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


let AiCreateSheetView_HEIGHT: CGFloat = 670.0 // シート表示時の高さ指定

/// パックをAIで生成　シート
struct AiCreateSheetView: View {
    /// 編集中のパックを保持し、AIへ修正依頼するときの素材にする
    private let basePack: M1Pack?


    @Environment(\.dismiss) private var dismiss
    /// TextEditorにフォーカスが当たっているかどうかを追跡するフォーカス状態
    @FocusState private var isRequirementFocused: Bool

    
    /// - Parameter basePack: 修正元としてAIへ渡したいパック（未指定なら新規作成として扱う）
    init(basePack: M1Pack? = nil) {
        self.basePack = basePack
    }

    var body: some View {
        let title = (basePack == nil || basePack!.name.isEmpty)
                    ? String(localized:"新しいパックを作ってもらう")
                    : String(localized:"【変更】 ") + (basePack?.name ?? "")

        NavigationView {
            ScrollView {
                AiCreateView(requirementFocus: $isRequirementFocused,
                             basePack: basePack)
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // 閉じる
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
}


/// AIで新しいパックを生成するためのビュー
struct AiCreateView: View {
    /// フォーカス制御を外部（親ビュー）から受け取るためのバインディング
    private let requirementFocus: FocusState<Bool>.Binding
    /// AIへ渡す修正対象パック（nilならAIは新規提案モード）
    private let basePack: M1Pack?

    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @EnvironmentObject private var creditStore: CreditStore

    /// ユーザーからAIへの要望・要件テキスト
    /// AppStorageを利用してシートを閉じても入力内容を保持する
    @AppStorage(AppStorageKey.aiRequirementText) private var requirementText: String = ""
    /// 設定画面で選択した「新規パックの追加位置」を参照し、インポート時にも統一した挙動にする
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    /// 購入通知済みのトランザクションIDを永続化し、アプリ再起動後も重複アラートを抑止する
    @AppStorage(AppStorageKey.aiPurchaseNotifiedTransactionIds) private var notifiedTransactionIdsBackup: Data = Data()
    /// 広告視聴で貯まる特典アイコン数（チャッピー送信用のスタンプ）
    @AppStorage(AppStorageKey.aiAdRewardStamps) private var adRewardStamps: Int = 0
    /// チャッピー送信に必要な特典アイコンの目安（スタンプ3個で1回無料）
    private let adRewardStampGoal = 3
    /// インポート処理やプロンプト転送の状態を伝えるためのアラート（課金系など通知しづらい内容に限定）
    @State private var alertState: AlertState?
    /// azuki-apiリクエスト中であることを示すフラグ
    @State private var isGenerating = false
    /// 生成処理の結果を画面内に表示して利用者へ知らせるためのフィードバック
    @State private var inlineGenerationFeedback: GenerationFeedback?
    /// アプリ内でクレジット購入を行う際の進行中商品ID（nilなら待機中）
    @State private var processingProductId: String?
    /// StoreKit 2 で取得した商品情報をキャッシュしておき、複数回の購入ボタンタップで再利用する
    @State private var storeProducts: [Product] = []
    /// 初回表示時にサーバー残高とKeychain残高を同期したかどうかのフラグ
    @State private var didRequestInitialBalance = false
    /// 広告視聴により一時的に利用できる特典があるかどうか
    /// StoreKitのトランザクション更新ストリームを監視するためのタスク
    @State private var transactionObservationTask: Task<Void, Never>?
    /// すでにユーザーへ通知済みのトランザクションIDを記録し、同じ購入結果のアラートを連続表示しないようにする
    @State private var notifiedTransactionIds: Set<String> = []
    /// ビューが画面上に表示されているかどうかを保持し、通知とアラートの出し分けに利用する
    @State private var isViewVisible = true
    /// 広告特典バッジからAdMobの広告シートを開くためのフラグ（動画視聴導線を明示）
    @State private var isPresentingAdRewardSheet = false

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// クレジット枚数だけで送信できるかどうか
    private var hasTicketForGeneration: Bool {
        CHATGPT_GENERATION_CREDIT_COST <= creditStore.credits
    }

    /// 広告視聴で貯まったスタンプがチャッピー送信に必要な3個へ到達しているか
    private var hasAdRewardTicket: Bool {
        if adRewardStamps < adRewardStampGoal {
            return false
        }
        return true
    }

    /// 入力とローディング状態、手持ちの特典から送信可否を算出する
    private var canSendRequest: Bool {
        if isRequirementEmpty {
            return false
        }
        if isGenerating {
            return false
        }
        if hasAdRewardTicket {
            return true
        }
        return hasTicketForGeneration
    }

    /// 端末に保存済みの通知済みトランザクションIDをStateへ復元する
    private func loadNotifiedTransactionIdsIfNeeded() {
        // 既にメモリ上へ読み込んでいれば追加で復元する必要はない
        if notifiedTransactionIds.isEmpty == false {
            return
        }
        // デコードが失敗した場合は空集合を維持し、重複アラート抑止だけを安全に続ける
        do {
            if notifiedTransactionIdsBackup.isEmpty {
                return
            }
            let decoded = try JSONDecoder().decode(Set<String>.self, from: notifiedTransactionIdsBackup)
            notifiedTransactionIds = decoded
        } catch {
            // 破損データは握りつぶし、次回以降に正しいJSONへ置き換える
            notifiedTransactionIds = []
        }
    }

    /// 通知済みリストを永続化し、アプリの再起動後も重複通知を避ける
    private func persistNotifiedTransactionIds() {
        do {
            let data = try JSONEncoder().encode(notifiedTransactionIds)
            notifiedTransactionIdsBackup = data
        } catch {
            // 永続化に失敗しても致命的ではないため、ログ出力のみに留める
            print("failed to persist notifiedTransactionIds: \(error)")
        }
    }

    /// トランザクションIDを通知済みとして登録し、即座に保存する
    /// - Parameter identifier: StoreKitトランザクションのID文字列
    private func markTransactionAsNotified(_ identifier: String) {
        notifiedTransactionIds.insert(identifier)
        persistNotifiedTransactionIds()
    }

    /// 親ビューからフォーカス制御のバインディングを受け取るためのイニシャライザ
    /// - Parameter requirementFocus: TextEditorのフォーカスを外部で管理するためのバインディング
    init(requirementFocus: FocusState<Bool>.Binding,
         basePack: M1Pack?) {
        self.requirementFocus = requirementFocus
        self.basePack = basePack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // セクションタイトル
            Label {
                Text("チャッピー(AI)に依頼する")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }

            // 操作説明（アプリ内生成の流れを簡潔に案内）
            Text("""
                要望を入力して「送信」ボタンを押せば、チャッピーにパックの作成や変更を依頼できます。チャッピーから届いた提案を眺めて修正しながらご利用ください。AI利用券1枚で1回の送信が可能です
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            
            VStack(alignment: .leading, spacing: 6) {
                // 利用券表示と送信ボタンをヘッダーとしてまとめ、操作の一体感を出す
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI利用券残り \(creditStore.credits) 枚")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                    }
                    Spacer()
                    // 送信
                    Button {
                        // 送信ボタンを押した瞬間にフォーカスを解除し、キーボードを閉じる
                        // TextEditorのバインディングフォーカスに直接アクセスして明示的に外す
                        requirementFocus.wrappedValue = false
                        // ボタンタップ時点で前回のフィードバックをいったん消し、最新状態だけを残す
                        inlineGenerationFeedback = nil
                        // 新規リクエストを確実に送るため、既存の処理を呼び出す
                        generatePackWithOpenAI()
                    } label: {
                        HStack(spacing: 6) {
                            if isGenerating {
                                // 読み込み中の様子をユーザーに知らせる
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }else{
                                if hasAdRewardTicket {
                                    Text(String(localized: "1回無料"))
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                                // 送信アイコン
                                Image(systemName: "paperplane")
                                    .imageScale(.medium)
                                    .symbolRenderingMode(.hierarchical)
                            }

                            Text(isGenerating ? "提案を考え中" : "送信")
                                .font(.callout.weight(.semibold))
                        }
                        .padding(.vertical, -4)
                        .padding(.horizontal, 4)
                    }
                    .disabled(canSendRequest == false)
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.horizontal, 8)

                // 入力欄とプレースホルダーをカード調レイアウトに収める
                ZStack(alignment: .topLeading) {
                    // 入力欄。カード背景と馴染むよう余白のみを加える
                    TextEditor(text: $requirementText)
                        .frame(height: 200)
                        .padding(2)
                        .focused(requirementFocus)
                        .background(Color.clear)
                        .accessibilityLabel(Text("パックの要望入力"))
                        // 入力文字数をAI_REQUIREMENT_MAX文字以内に抑えるための監視
                        .onChange(of: requirementText) { newValue, _ in
                            // 文字数が上限以下ならそのまま利用する
                            if newValue.count <= AI_REQUIREMENT_MAX {
                                return
                            }
                            // 超えた分は切り捨てて保存し直す
                            let limitedText = String(newValue.prefix(AI_REQUIREMENT_MAX))
                            requirementText = limitedText
                        }

                    // プレースホルダー
                    if isRequirementEmpty {
                        // 入力例。TextEditorの内側余白と揃えて配置
                        Text((self.basePack == nil || self.basePack!.name.isEmpty) ?
                            """
                            訪問先、日程、目的、人数、気候、アクティビティなどの要望をたくさん列記してください
                            （最大\(AI_REQUIREMENT_MAX)文字）
                            （例）海外旅行5泊6日、イタリア、スペイン、家族4人、雨天も想定、救急用品も持参
                            """
                             :
                            """
                            変更の要望をたくさん列記してください
                            （最大\(AI_REQUIREMENT_MAX)文字）
                            （例）6泊に変更、ギリシャも訪問、祖父母も参加
                            """)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .allowsHitTesting(false) // タップを奪わないようにヒットテストを無効化
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        Color(uiColor: colorScheme == .dark ? .tertiarySystemBackground : .systemGray3)
                    )
            )
            
            if isGenerating {
                Text("チャッピーが考えています。提案が届けば通知しますので、閉じても大丈夫です。他の操作をしてお楽しみください")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.blue)
            }

            // 送信結果メッセージ
            if let feedback = inlineGenerationFeedback {
                // 成功と失敗で色やアイコンを切り替え、視覚的に状態を把握しやすくする
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: feedback.iconName)
                        .foregroundStyle(feedback.tintColor)
                        .accessibilityHidden(true)
                    Text(feedback.message)
                        .font(.body.weight(.medium))
                        .foregroundStyle(feedback.tintColor)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(feedback.backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(feedback.tintColor.opacity(0.3), lineWidth: 1)
                )
            }

            // AI利用券購入
            creditPurchaseMenu
            
            Divider()
                .padding(.vertical, 4)
            
            // 広告を見て特典をゲット　リワード広告
            adRewardBadge
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // バッジタップでAdMobの広告シートを重ねて開き、特典取得へ誘導する
        .sheet(isPresented: $isPresentingAdRewardSheet) {
            AdMobAdSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            // シートが表示されたら画面内フィードバックを優先で伝えるためのフラグを立てる
            isViewVisible = true
            // 古い結果メッセージが残っていると誤解を招くので表示のたびにリセットする
            inlineGenerationFeedback = nil
            // アプリ再起動後でも重複アラートを抑止できるよう、保存しておいたトランザクションIDを復元する
            loadNotifiedTransactionIdsIfNeeded()
        }
        .task {
            // AzukiApiへトークン復旧ロジックを注入しておくことで、Keychainが空でも即座に復旧できるようにする
            await AzukiApi.shared.registerTokenRecoveryHandler {
                await recoverAccessTokenByVerifyingLatestTransactions()
            }
            // 初回表示時に商品情報を取得しつつ、サーバー残高との同期も直ちに行う
            await loadProductsIfNeeded()
            // サーバー残高との同期は一度だけ実行し、Keychainの値と揃えておく
            await syncCreditStatusIfNeeded()
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
            // 画面から離れたので、以降はローカル通知で結果を伝える
            isViewVisible = false
            // 画面を閉じるときに表示中のメッセージも消去して、再表示時に新鮮な状態で始められるようにする
            inlineGenerationFeedback = nil
            // ビューが消えた後は復旧ハンドラを解除し、不要な保持を避ける
            Task {
                await AzukiApi.shared.clearTokenRecoveryHandler()
            }
            // メモリ上の通知済みリストを保存し、アプリ再起動後も同じ購入でアラートが重複しないようにする
            persistNotifiedTransactionIds()
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

    /// 広告視聴で獲得した「1回無料」特典のバッジ
    private var adRewardTicketChip: some View {
        HStack(spacing: 6) {
            // チャッピー送信に使える無料特典が存在することをアイコンで示す
            Image(systemName: "gift.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            // 次の送信が無料であることをテキストで補足する
            Text(String(localized: "特典1回無料"))
                .font(.caption)
        }
//        .padding(.vertical, 3)
        .padding(.horizontal, 4)
//        .background(
//            Capsule(style: .continuous)
//                .fill(Color.brown.opacity(0.18))
//        )
//        .overlay(
//            Capsule(style: .continuous)
//                .stroke(Color.red, lineWidth: 1)
//        )
//        .foregroundStyle(.primary)
    }

    /// 広告特典の状態を示すバッジ
    private var adRewardBadge: some View {
        VStack(alignment: .center, spacing: 4) {
            Button {
                // 1タップで広告シートを開き、動画視聴から特典獲得へつなげる
                isPresentingAdRewardSheet = true
            } label: {
                HStack(spacing: 8) {
                    ForEach(0..<adRewardStampGoal, id: \.self) { index in
                        let filled = index < adRewardStamps
                        Image(systemName: filled ? "movieclapper.fill" : "movieclapper")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(filled ? Color.blue : Color.secondary)
                    }
                    Text("広告を見て特典をゲット")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                }
                .padding(.horizontal, 8)
            }
            // ボタンらしさを抑え、既存バッジの見た目を維持する
            .buttonStyle(.borderedProminent)
            .tint(.accentColor.opacity(0.3))
            
            Text("動画広告を3回視聴すると送信が1回無料になります")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity) // 中央寄せのために必要
    }
    
    /// azuki-api経由でOpenAIにパック生成を依頼する
    private func generatePackWithOpenAI() {
        // 進行中の生成リクエストがあれば新しい処理を開始せず、送信ボタンの連打を抑止する
        if isGenerating {
            return
        }
        isGenerating = true

        let trimmedRequirement = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRequirement.isEmpty {
            inlineGenerationFeedback = .failure(message: String(localized: "パック作成の要望を入れてね"))
            isGenerating = false
            return
        }

        let userId = creditStore.userId
        Task {
            // deferで生成処理終了後の共通後片付け（ローカル残高の戻しとローディング解除）をまとめる
            let cost = CHATGPT_GENERATION_CREDIT_COST
            var shouldRestoreCredits = false
            var shouldRestoreAdReward = false
            defer {
                Task {
                    await MainActor.run {
                        if shouldRestoreCredits {
                            // サーバー側で消費されなかったと推定される場合はローカル残高を戻す
                            creditStore.add(credits: cost)
                        }
                        if shouldRestoreAdReward {
                            adRewardStamps += adRewardStampGoal
                        }
                        isGenerating = false
                    }
                }
            }

            // 毎回送信前に最新の残高と特典情報をサーバーへ確認し、トークン配布も拾う
            let didSyncCreditStatus = await refreshCreditStatusBeforeSending(userId: userId)
            if didSyncCreditStatus == false {
                return
            }

            // サーバー結果で特典スタンプが補充されたかもしれないので、最新値を見て特典利用判定を行う
            let usesAdReward = await MainActor.run { hasAdRewardTicket }

            // ローカル残高が不足している場合に限り不足フィードバックを出す（Keychain保存なので通信不要）
            if usesAdReward == false {
                let hasEnoughCredits = await ensureSufficientCreditsForGeneration(cost: cost)
                if hasEnoughCredits == false {
                    await presentCreditShortageFeedback()
                    return
                }

                do {
                    try await MainActor.run {
                        try creditStore.consume(credits: cost)
                        shouldRestoreCredits = true
                    }
                } catch {
                    await presentCreditShortageFeedback()
                    return
                }
            } else {
                await MainActor.run {
                    // 広告特典がある場合は優先的に利用し、同時にローカルのスタンプ数を減らして重複消費を防ぐ
                    let remaining = adRewardStamps - adRewardStampGoal
                    if remaining < 0 {
                        adRewardStamps = 0
                    } else {
                        adRewardStamps = remaining
                    }
                }
                shouldRestoreAdReward = true
            }

            do {
                let basePackDTO = await exportBasePackIfAvailable()
                let dto = try await requestPackFromServer(
                    userId: userId,
                    requirement: trimmedRequirement,
                    basePack: basePackDTO,
                    canAttemptRecovery: true
                )
                // サーバー側ではすでにクレジットが消費済みとみなし、戻しは行わない
                shouldRestoreCredits = false
                shouldRestoreAdReward = false
                do {
                    let packName = try await MainActor.run { () -> String in
                        let importedPack = try createPack(from: dto)

                        GALogger.log(.packlin_request(userId: userId,
                                                      requirement: trimmedRequirement))
                        // 生成が成功しクレジット消費も確定したので、次回表示時に空欄から始められるよう保存済みの要望文を消す
                        requirementText = ""
                        return importedPack.name
                    }
                    // シート表示中は画面内メッセージ、閉じた後はローカル通知と使い分けて知らせる
                    await presentGenerationSuccess(packName: packName)
                } catch {
                    let message: String
                    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                        message = description
                    } else {
                        message = error.localizedDescription
                    }
                    await presentGenerationFailure(message: message)
                }
            } catch let apiError as AzukiAPIError {
                // API起因のエラーは内容に応じて処理。ローカル残高はdeferで戻す。
                switch apiError {
                case .insufficientCredits:
                    // サーバー側で不足判定となったのでローカルを戻さず、Keychain残高を最新状態で使い続ける
                    shouldRestoreCredits = false
                    // サーバーの残高を参照してKeychainを最新化し、複数端末での消費にも追随させる
                    await refreshCreditStatusFromServer(showAlertOnFailure: false)
                    await presentCreditShortageFeedback()
                case .unauthorized, .forbiddenUser, .missingAuthToken, .tokenExpired:
                    let message = apiError.errorDescription
                    ?? String(localized: "認証に失敗しました。アプリを再起動して再度お試しください")
                    await presentGenerationFailure(message: message)
                default:
                    let message = apiError.errorDescription
                    ?? String(localized: "チャッピーが忙しそうです。時間をおいて再度お試しください")
                    await presentGenerationFailure(message: message)
                }
            } catch let localized as LocalizedError {
                let message = localized.errorDescription ?? localized.localizedDescription
                await presentGenerationFailure(message: message)
            } catch {
                await presentGenerationFailure(message:
                                                    String(localized: "チャッピーが忙しそうです。時間をおいて再度お試しください"))
            }
        }
    }

    /// 送信直前にサーバーへ問い合わせ、残高と特典フラグ、トークン配布状況を同期する
    /// - Parameter userId: アクセス対象のユーザーID
    /// - Returns: 正常に同期できた場合はtrue
    private func refreshCreditStatusBeforeSending(userId: String) async -> Bool {
        do {
            // トークン未取得でもアクセスできるAPIなので、送信ごとに実行して最新状態を確実に取得する
            let status = try await AzukiApi.shared.fetchCreditStatus(userId: userId)
            await MainActor.run {
                // サーバー残高でローカルを上書きし、他端末の消費や無料特典の付与を確実に反映する
                creditStore.overwrite(credits: status.balance)
                if status.adRewardAvailable {
                    if adRewardStamps < adRewardStampGoal {
                        adRewardStamps = adRewardStampGoal
                    }
                }
            }
            // fetchCreditStatus 内でトークンが返却されるため、ここでは成功可否のみ返す
            return true
        } catch let apiError as AzukiAPIError {
            // 通信エラーなどで送信前の確認に失敗した場合は、ユーザーへ通知し送信を中断する
            let message = apiError.errorDescription
            ?? String(localized: "AI利用が可能か確認できません。通信環境をご確認ください")
            await presentGenerationFailure(message: message)
            return false
        } catch {
            let message = String(localized: "AI利用が可能か確認できません。通信環境をご確認ください")
            await presentGenerationFailure(message: message)
            return false
        }
    }

    /// 生成成功をユーザーへ伝える。画面表示中は画面内メッセージ、閉じていればローカル通知で知らせる
    /// - Parameter packName: 生成に成功したパック名
    private func presentGenerationSuccess(packName: String) async {
        let viewVisible = await MainActor.run { isViewVisible }
        if viewVisible {
            await MainActor.run {
                inlineGenerationFeedback = .success(message: String(localized: "チャッピーの提案によりパックを更新しました。さらにカスタマイズしてご利用ください"))
            }
            return
        }
        await LocalNotificationManager.shared.notifyPackGenerationSucceeded(packName: packName)
    }

    /// 生成失敗をユーザーへ伝える。画面表示中は画面内メッセージ、閉じていればローカル通知で知らせる
    /// - Parameter message: 利用者へ伝える詳細メッセージ
    private func presentGenerationFailure(message: String) async {
        let viewVisible = await MainActor.run { isViewVisible }
        if viewVisible {
            await MainActor.run {
                inlineGenerationFeedback = .failure(message: message)
            }
            return
        }
        await LocalNotificationManager.shared.notifyPackGenerationFailed(message: message)
    }

    /// クレジット不足時のフィードバック。画面表示中は画面内メッセージ、閉じていれば失敗通知を送る
    private func presentCreditShortageFeedback() async {
        let viewVisible = await MainActor.run { isViewVisible }
        if viewVisible {
            await MainActor.run {
                inlineGenerationFeedback = .failure(message: String(localized: "AI利用券が不足しています。下のメニューから購入してください"))
            }
            return
        }
        await LocalNotificationManager.shared.notifyPackGenerationFailed(message: String(localized: "AI利用券が不足しています。下のメニューから購入してください"))
    }

    /// OpenAI経由の生成リクエストを実行し、必要に応じてトークン再取得を挟む
    /// - Parameters:
    ///   - userId: サーバー側でクレジット消費対象となるユーザーID
    ///   - requirement: ユーザーが入力した要件
    ///   - canAttemptRecovery: トークン再取得を試行できるかどうか（再帰呼び出し抑制用）
    /// - Returns: サーバーが返したPack生成結果DTO
    private func requestPackFromServer(userId: String,
                                       requirement: String,
                                       basePack: PackJsonDTO?,
                                       canAttemptRecovery: Bool) async throws -> PackJsonDTO {
        do {
            return try await AzukiApi.shared.generatePack(userId: userId,
                                                          requirement: requirement,
                                                          basePack: basePack)
        } catch let apiError as AzukiAPIError {
            if canAttemptRecovery && shouldAttemptTokenRecovery(for: apiError) {
                let recovered = await recoverAccessTokenByVerifyingLatestTransactions()
                if recovered {
                    return try await requestPackFromServer(
                        userId: userId,
                        requirement: requirement,
                        basePack: basePack,
                        canAttemptRecovery: false
                    )
                }
            }
            throw apiError
        }
    }

    /// 編集中のパックがあればDTOへ変換し、APIへ送る準備をする
    private func exportBasePackIfAvailable() async -> PackJsonDTO? {
        guard let basePack else {
            return nil
        }
        return await MainActor.run {
            // SwiftDataのモデルへアクセスするためMainActor上でJSON化する
            basePack.exportRepresentation()
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
        do {
            // クレジット残高照会APIは未認証でも受け付けるため、最初にここでトークンを再配布してもらう
            let status = try await AzukiApi.shared.fetchCreditStatus(userId: userId)
            await MainActor.run {
                // サーバーの残高でローカル状態も揃え、広告特典の獲得可否も同期しておく
                creditStore.overwrite(credits: status.balance)
                if status.adRewardAvailable && adRewardStamps < adRewardStampGoal {
                    adRewardStamps = adRewardStampGoal
                }
            }
            if AzukiApi.shared.hasValidAccessToken() {
                // 残高照会だけでアクセストークンが配られた場合はここで復旧完了とする
                return true
            }
        } catch let apiError as AzukiAPIError {
            // ここで失敗しても購入履歴をたどるリカバリは継続し、通信状況の揺らぎに備える
            #if DEBUG
            print("[AzukiApi] credit check for recovery failed: \(apiError)")
            #endif
        } catch {
            #if DEBUG
            print("[AzukiApi] unexpected error while recovering via credit check: \(error)")
            #endif
        }
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
                        await refreshCreditStatusFromServer(showAlertOnFailure: false)
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
    private func syncCreditStatusIfNeeded() async {
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
        await refreshCreditStatusFromServer(showAlertOnFailure: false)
    }

    /// サーバーに保存されている残高を取得してKeychainへ反映する
    /// - Parameter showAlertOnFailure: 失敗時にユーザーへアラート表示するかどうか
    private func refreshCreditStatusFromServer(showAlertOnFailure: Bool) async {
        let userId = await MainActor.run { creditStore.userId }
        do {
            // azuki-apiへ問い合わせて最新残高を受け取り、Keychainに保持している値と揃える
            let status = try await AzukiApi.shared.fetchCreditStatus(userId: userId)
            await MainActor.run {
                creditStore.overwrite(credits: status.balance)
                // サーバーが「広告特典を使える」と返した場合はスタンプを3個ぶん確保しておく
                if status.adRewardAvailable {
                    if adRewardStamps < adRewardStampGoal {
                        adRewardStamps = adRewardStampGoal
                    }
                }
            }
        } catch let apiError as AzukiAPIError {
            if showAlertOnFailure {
                let message = apiError.errorDescription
                ?? String(localized: "AI利用が可能か確認できません。通信環境をご確認ください")
                await MainActor.run {
                    inlineGenerationFeedback = .failure(message: message)
                }
            }
            #if DEBUG
            print("[AzukiApi] failed to refresh balance: \(apiError)")
            #endif
        } catch {
            if showAlertOnFailure {
                await MainActor.run {
                    inlineGenerationFeedback = .failure(message: String(localized: "AI利用が可能か確認できません。通信環境をご確認ください"))
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
            // 残高が1枚以上残っている場合は購入処理を遮断する
            let currentCredits = await MainActor.run { creditStore.credits }
            if 0 < currentCredits {
                await MainActor.run {
                    alertState = .purchaseBlockedByRemaining
                    processingProductId = nil
                }
                return
            }

            await MainActor.run {
                // 複数ボタンが並ぶため、購入中の選択肢のみローディング表示へ切り替える
                processingProductId = productId
            }

            let msgPurchaseCancel = String(localized: "購入を中止しました、課金されません")
            
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
                            alertState = .purchaseFailure(message: String(localized: "購入の承認待ちです、まだ課金されません。承認が完了すると自動で反映されます"))
                        }
                        
                    case .userCancelled:
                        // ユーザーがキャンセルした場合は状況を伝えるメッセージを表示
                        await MainActor.run {
                            alertState = .purchaseFailure(message: msgPurchaseCancel)
                        }
                        
                    @unknown default:
                        await MainActor.run {
                            alertState = .purchaseFailure(message: String(localized: "想定外の結果が返りました、課金されません。時間をおいて再度お試しください"))
                        }
                }
            } catch let flowError as PurchaseFlowError {
                await MainActor.run {
                    let message = flowError.errorDescription
                        ?? String(localized: "AI利用券が購入できませんでした、課金されません")
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
                    alertState = .purchaseFailure(message: String(localized: "AI利用券の購入中に問題が発生しました、課金されません。通信環境をご確認ください"))
                }
            }

            await MainActor.run {
                processingProductId = nil
            }
        }
    }

    /// AI利用券購入ボタンを横方向へ並べるためのグリッド定義
    private var purchaseGridColumns: [GridItem] {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return columns
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

            // Config側で定義した金額・クレジットの対応表を横並びのグリッドで描画する
            LazyVGrid(columns: purchaseGridColumns, alignment: .center, spacing: 12) {
                ForEach(AZUKI_CREDIT_PURCHASE_OPTIONS, id: \.productIdJapan) { option in
                    Button {
                        // 横並びでも分かりやすいように、タップ操作の結果を明示
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
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor.opacity(1.0))
                    .disabled(processingProductId != nil || isPurchaseUnavailable(for: option))
                }
            }
            .padding(.horizontal, 12)

            if let warningMessage = purchaseRestrictionWarning {
                Text(warningMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            }

            Label {
                Text("AI利用券は端末に安全に保管されますが、端末が壊れたりアプリを削除すると失われます。貯めずに早めにお使いください")
                    .font(.footnote)
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
    private func isPurchaseUnavailable(for _: AzukiCreditPurchaseOption) -> Bool {
        // 画面表示中はMainActor上なので直接残高を参照してよい
        let currentCredits = creditStore.credits
        if 0 < currentCredits {
            // 残高があれば即座に購入ボタンを無効化する
            return true
        }
        return false
    }

    /// 現在の残高から購入制限メッセージを導出する
    private var purchaseRestrictionWarning: String? {
        let currentCredits = creditStore.credits
        if 0 < currentCredits {
            // 購入は残高ゼロ時のみ許可する旨をユーザーへ伝える
            return String(localized: "AI利用券が残っている間は購入できません、残りが0枚になってからご購入ください")
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
            localized: "購入を中止しました、課金されません")


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
                    markTransactionAsNotified(transactionIdentifier)
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
                await refreshCreditStatusFromServer(showAlertOnFailure: false)
                await MainActor.run {
                    if notifiedTransactionIds.contains(transactionIdentifier) == false {
                        // サーバー側で既に処理済みだった購入についても、一度だけ状況を知らせる
                        markTransactionAsNotified(transactionIdentifier)
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
                return String(localized: "商品情報が見つかりません")
            case .transactionUnverified(let message):
                return message
            }
        }
    }

    /// DTOからPackを作成してSwiftDataへ保存
    private func createPack(from dto: PackJsonDTO) throws -> M1Pack {
        // Undoグループでまとめて、失敗時にも綺麗に巻き戻せるようにする
        modelContext.undoManager?.groupingBegin()
        defer {
            modelContext.undoManager?.groupingEnd()
        }

        if let basePack {
            // 既存パックが指定されている場合は、新規追加せず中身を丸ごと差し替える
            return PackImporter.overwrite(pack: basePack,
                                          with: dto,
                                          in: modelContext)
        }

        // 新規作成時は既存パックの並びと設定で指定された挿入位置を考慮して order を決定する
        // AppStorageの設定値を反映することでAI生成も通常追加と同じ位置に並ぶ
        let descriptor = FetchDescriptor<M1Pack>()
        let packs = (try? modelContext.fetch(descriptor)) ?? []
        let orderedPacks = packs.sorted { $0.order < $1.order }
        let insertionIndex: Int = {
            switch insertionPosition {
            case .head:
                // 先頭に追加する場合は index 0
                return 0
            case .tail:
                // 末尾へ追加する場合は要素数と同じ位置に挿入
                return orderedPacks.count
            }
        }()
        let newOrder = sparseOrderForInsertion(items: orderedPacks, index: insertionIndex) {
            // 隙間が足りない場合は正規化して order の整合性を保つ
            normalizeSparseOrders(orderedPacks)
        }

        return PackImporter.insertPack(from: dto, into: modelContext, order: newOrder)
    }

    /// 生成結果を画面内で伝えるための簡易ステータス
    private enum GenerationFeedback: Equatable {
        /// 成功時のメッセージ
        case success(message: String)
        /// 失敗時のメッセージ
        case failure(message: String)

        /// ラベルに表示する文言
        var message: String {
            switch self {
            case .success(let message):
                return message
            case .failure(let message):
                return message
            }
        }

        /// 成功／失敗に応じた色味
        var tintColor: Color {
            switch self {
            case .success:
                return Color.green
            case .failure:
                return Color.red
            }
        }

        /// 背景色を薄く敷いて可読性を高める
        var backgroundColor: Color {
            switch self {
            case .success:
                return Color.green.opacity(0.12)
            case .failure:
                return Color.red.opacity(0.12)
            }
        }

        /// 状態に合わせたアイコンを返す
        var iconName: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .failure:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    /// アラート表示用の状態定義
    private enum AlertState: Identifiable {
        /// クレジット購入が成功した場合
        case purchaseSuccess(added: Int, productId: String)
        /// サーバー側ですでに反映済みの購入だった場合
        case purchaseAlreadyProcessed
        /// クレジット購入が失敗した場合
        case purchaseFailure(message: String)
        /// 残高が残っているため購入できない場合
        case purchaseBlockedByRemaining

        var id: String {
            switch self {
            case .purchaseSuccess(let added, let productId):
                return "ai-purchaseSuccess-\(added)-\(productId)"
            case .purchaseAlreadyProcessed:
                return "ai-purchaseAlreadyProcessed"
            case .purchaseFailure(let message):
                return "ai-purchaseFailure-\(message)"
            case .purchaseBlockedByRemaining:
                return "ai-purchaseBlockedByRemaining"
            }
        }

        var title: String {
            switch self {
                case .purchaseSuccess:
                    return String(localized: "購入手続きが完了しました")
                    // このメッセージの前に出る同様のアラートは、Sandboxでのみ表示される。本番では表示されない
                case .purchaseAlreadyProcessed:
                    return String(localized: "既に購入済みです")
                case .purchaseFailure:
                    return String(localized: "購入状況")
                case .purchaseBlockedByRemaining:
                    return String(localized: "購入状況")
            }
        }

        var message: String {
            switch self {
                case .purchaseSuccess(let added, _):
                    return String(localized: "AI利用券を\(added)枚追加しました")
                case .purchaseAlreadyProcessed:
                    return String(localized: "この購入はすでに完了しています、枚数を更新しました")
                case .purchaseFailure(let message):
                    return message
                case .purchaseBlockedByRemaining:
                    return String(localized: "AI利用券が残っている間は購入できません、残りが0枚になってからご購入ください")
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
            if let directString = String(data: self.signedData, encoding: .utf8), directString.contains(".") {
                // ここではすでに "header.payload.signature" 形式の完全なJWS文字列が得られているケースを最優先で返す
                // iOS 18 での挙動変更により Data 型で受け取っても中身がプレーン文字列のことがあるため、この早期リターンが重要
                return directString
            }
            // directString が取得できない場合は Base64 デコードを試し、復号後に UTF-8 文字列化してサーバーへ送る
            if let decodedData = Data(base64Encoded: self.signedData),
               let decodedString = String(data: decodedData, encoding: .utf8),
               decodedString.contains(".") {
                // Base64 文字列だった場合も UTF-8 テキストに復号したあとにJWS構造かを判定し、正規化したものを返す
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
