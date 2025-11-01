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
    /// 既存パックをチャット経由で更新する場合に対象となるパック
    private let pack: M1Pack?

    init(pack: M1Pack? = nil) {
        self.pack = pack
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    AiCreateView(
                        pack: pack,
                        requirementFocus: $isRequirementFocused,
                        scrollProxy: proxy
                    )
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

/// チャット履歴1件を保持するモデル
struct AiChatMessage: Identifiable, Codable, Equatable {
    /// メッセージの送り手
    enum Role: String, Codable {
        case user
        case assistant

        /// APIへ送る際に識別しやすい大文字タグ
        var serverTag: String {
            switch self {
            case .user:
                return "USER"
            case .assistant:
                return "ASSISTANT"
            }
        }

        /// 表示上、ユーザー発言かどうかのブール値
        var isUser: Bool {
            self == .user
        }
    }

    let id: UUID
    let role: Role
    let content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// チャットの吹き出しを描画するビュー
private struct AiChatMessageBubble: View {
    let message: AiChatMessage

    var body: some View {
        HStack {
            if message.role.isUser {
                Spacer(minLength: 24)
                bubbleView
            } else {
                bubbleView
                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: message.id)
    }

    /// メッセージ本体の吹き出し
    private var bubbleView: some View {
        Text(message.content)
            .font(.callout)
            .multilineTextAlignment(.leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundStyle(textColor)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: borderLineWidth)
            )
    }

    /// 吹き出し背景色
    private var backgroundColor: Color {
        if message.role.isUser {
            return Color.accentColor
        }
        return Color(uiColor: .systemGray6)
    }

    /// 文字色
    private var textColor: Color {
        if message.role.isUser {
            return Color.white
        }
        return Color.primary
    }

    /// 吹き出しの枠線色
    private var borderColor: Color {
        if message.role.isUser {
            return Color.accentColor.opacity(0.6)
        }
        return Color.accentColor.opacity(0.25)
    }

    /// 吹き出しの枠線の太さ
    private var borderLineWidth: CGFloat {
        if message.role.isUser {
            return 0.6
        }
        return 1
    }
}

/// TextEditorの高さ変化をPreferenceで受け渡すためのキー
private struct TextEditorHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    /// 外側のスクロールビューを制御して、入力欄がキーボードに隠れないよう調整するためのプロキシ
    private let scrollProxy: ScrollViewProxy
    /// 保存するチャット履歴の最大件数（サーバーへ渡す文量を抑えるための安全弁）
    private let chatHistoryLimit = 30
    /// チャット開始時に案内として常に表示するアシスタントメッセージ
    private let initialAssistantMessage: AiChatMessage
    /// 初期表示時に紐付ける既存パック（nilなら新規作成モード）
    private let initialPack: M1Pack?
    /// チャット入力欄へスクロールする際に利用するアンカーID
    private let chatInputAnchorId = "aiChatInputAnchor"

    /// ユーザーからAIへの要望・要件テキスト。パックごとのドラフトはDBに残さずその場限りにする。
    @State private var requirementText: String = ""
    /// キーボード高さを監視して、スクロール位置を調整するためのオブジェクト
    @StateObject private var keyboardObserver = KeyboardObserver()
    /// インポート処理やプロンプト転送の状態を伝えるためのアラート（課金系など通知しづらい内容に限定）
    @State private var alertState: AlertState?
    /// azuki-apiリクエスト中であることを示すフラグ
    @State private var isGenerating = false
    /// 生成処理の結果を画面内に表示して利用者へ知らせるためのフィードバック
    @State private var inlineGenerationFeedback: GenerationFeedback?
    /// チャットメッセージ群（ユーザーとAIの往復を保持）
    @State private var chatMessages: [AiChatMessage] = []
    /// 送信中のドラフトメッセージ。失敗時に入力欄へ戻すため保持する
    @State private var pendingDraftMessage: String?
    /// 現在チャットで操作しているパック
    @State private var currentPack: M1Pack?
    /// AppStorageから履歴を復元済みかどうかのフラグ（多重読み込み防止）
    @State private var didLoadChatHistory = false
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
    /// ビューが画面上に表示されているかどうかを保持し、通知とアラートの出し分けに利用する
    @State private var isViewVisible = true
    /// TextEditorの表示高さを保持し、行数増加時にスクロールを追従させる
    @State private var textEditorHeight: CGFloat = 0

    /// ユーザー入力が空かどうかを判定し、ボタン活性状態に利用する
    private var isRequirementEmpty: Bool {
        requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 送信ボタンを無効化する条件の集約
    private var isSendButtonInactive: Bool {
        isRequirementEmpty || isGenerating
    }

    /// 親ビューからフォーカス制御のバインディングを受け取るためのイニシャライザ
    /// - Parameter requirementFocus: TextEditorのフォーカスを外部で管理するためのバインディング
    init(pack: M1Pack?, requirementFocus: FocusState<Bool>.Binding, scrollProxy: ScrollViewProxy) {
        self.requirementFocus = requirementFocus
        self.initialPack = pack
        self._currentPack = State(initialValue: pack)
        self.scrollProxy = scrollProxy
        // 利用者へ聞きたい内容をあらかじめ吹き出しで表示して案内する
        self.initialAssistantMessage = AiChatMessage(
            role: .assistant,
            content: String(localized: "旅先や目的、行程、人数、季節、アクティビティなど教えて")
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // セクションタイトル
            Label {
                Text("チャッピー(AI)に相談する")
                    .font(.body.weight(.bold))
            } icon: {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }

            // 操作説明（アプリ内生成の流れを簡潔に案内）
            Text("チャットで相談しましょう。チャッピーが要望に応じたパックを提案してくれます。送信の都度AI利用券1枚が必要です")
                .font(.body)
                .foregroundStyle(.secondary)
            
            // チャット履歴を表示する領域
            VStack(alignment: .leading, spacing: 8) {
//                Text(String(localized: "AIとのチャット履歴"))
//                    .font(.caption)
//                    .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            // いつでも一番上にガイド用のメッセージを表示する
                            AiChatMessageBubble(message: initialAssistantMessage)
                                .id(initialAssistantMessage.id)
                                .padding(.bottom, chatMessages.isEmpty ? 8 : 4)

                            ForEach(chatMessages) { message in
                                AiChatMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 100, maxHeight: 300)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: chatMessages) { messages in
                        if let last = messages.last {
                            DispatchQueue.main.async {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onAppear {
                        if let last = chatMessages.last {
                            DispatchQueue.main.async {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // チャット入力欄
            chatInputSection
                .id(chatInputAnchorId)
                .padding(.top, -12)

            if isGenerating {
                Text("チャッピーが考えてます。できあがれば通知しますので、他の操作をしてお楽しみください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let feedback = inlineGenerationFeedback {
                // 成功と失敗で色やアイコンを切り替え、視覚的に状態を把握しやすくする
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: feedback.iconName)
                        .foregroundStyle(feedback.tintColor)
                        .accessibilityHidden(true)
                    Text(feedback.message)
                        .font(.footnote)
                        .foregroundStyle(feedback.tintColor)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(feedback.backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(feedback.tintColor.opacity(0.3), lineWidth: 1)
                )
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
        .padding(.bottom, keyboardObserver.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // SwiftDataに保存していたチャット履歴を復元
            restoreChatHistoryIfNeeded()
            // シートが表示されたら画面内フィードバックを優先で伝えるためのフラグを立てる
            isViewVisible = true
            // 古い結果メッセージが残っていると誤解を招くので表示のたびにリセットする
            inlineGenerationFeedback = nil
            // 初期表示でも入力欄が見える位置に合わせておく
            scrollToChatInput(animated: false)
        }
        .onChange(of: chatMessages) { _ in
            persistChatHistory()
        }
        .onChange(of: keyboardObserver.height) { _ in
            // キーボードが出入りしたら入力欄へスクロールして視界に収める
            scrollToChatInput(animated: true)
        }
        .onChange(of: requirementFocus.wrappedValue) { isFocused in
            if isFocused {
                // 利用者が入力欄をタップした瞬間にもスクロールしておく
                scrollToChatInput(animated: true)
            }
        }
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
            // 画面から離れたので、以降はローカル通知で結果を伝える
            isViewVisible = false
            // 画面を閉じるときに表示中のメッセージも消去して、再表示時に新鮮な状態で始められるようにする
            inlineGenerationFeedback = nil
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

    /// 履歴直下に配置するチャット入力欄（キーボードで隠れないようスクロール連動）
    private var chatInputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $requirementText)
                        //.focused(requirementFocus)
                        .frame(minHeight: 24, maxHeight: 160)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        // TextEditorの枠線をなるべくシンプルにしつつ読みやすさを保つ
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(uiColor: .systemBackground))
                                )
                        )
                        .accessibilityLabel(Text("パックの要望入力"))
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: TextEditorHeightPreferenceKey.self,
                                        value: geometry.size.height
                                    )
                            }
                        )

//                    if requirementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//                        Text(String(localized: "旅程や持ち物の希望を入力"))
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                            .padding(.vertical, 12)
//                            .padding(.horizontal, 14)
//                            .allowsHitTesting(false)
//                    }
                }

                Button {
                    sendDraftMessage()
                } label: {
                    HStack(spacing: 6) {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .imageScale(.medium)
                        }
                        Text(isGenerating ? String(localized: "送信中") : String(localized: "送信"))
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSendButtonInactive ? Color.gray.opacity(0.3) : Color.accentColor)
                    )
                    .foregroundStyle(isSendButtonInactive ? Color.white.opacity(0.7) : Color.white)
                }
                .disabled(isSendButtonInactive)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
        )
        .onPreferenceChange(TextEditorHeightPreferenceKey.self) { newHeight in
            // TextEditorが広がったら即座にスクロールし、キーボードに隠れない位置を保つ
            if textEditorHeight + 0.5 < newHeight {
                textEditorHeight = newHeight
                scrollToChatInput(animated: true)
            } else {
                textEditorHeight = newHeight
            }
        }
    }

    /// 背景カラーをダーク／ライトに応じて出し分ける
    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(uiColor: .systemGray3)
        }

        return Color(uiColor: .systemGray6)
    }

    /// 入力欄が常に視界に入るよう、スクロール位置を最下部へ移動させる
    private func scrollToChatInput(animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo(chatInputAnchorId, anchor: .bottom)
                }
            } else {
                scrollProxy.scrollTo(chatInputAnchorId, anchor: .bottom)
            }
        }
    }

    /// チャット入力欄のテキストを送信し、履歴へ追加してから生成処理を開始する
    @MainActor
    private func sendDraftMessage() {
        let trimmed = requirementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            inlineGenerationFeedback = .failure(message:
                                        String(localized: "メッセージを入れてね"))
            return
        }
        if isGenerating {
            return
        }
        inlineGenerationFeedback = nil
        pendingDraftMessage = trimmed
        appendUserMessage(trimmed)
        requirementText = ""
        requirementFocus.wrappedValue = false
        // azuki-api経由でOpenAIにパック生成を依頼する
        generatePackWithOpenAI()
    }

    /// ユーザーのチャット発言を履歴へ追加する
    @MainActor
    private func appendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return
        }
        chatMessages.append(AiChatMessage(role: .user, content: trimmed))
        trimChatHistoryIfNeeded()
    }

    /// AIからの返信を履歴へ追加する
    @MainActor
    private func appendAssistantMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return
        }
        chatMessages.append(AiChatMessage(role: .assistant, content: trimmed))
        trimChatHistoryIfNeeded()
    }

    /// 履歴件数が上限を超えたときに古いものから削除する
    @MainActor
    private func trimChatHistoryIfNeeded() {
        let limit = chatHistoryLimit
        if limit < chatMessages.count {
            let overflow = chatMessages.count - limit
            chatMessages.removeFirst(overflow)
        }
    }

    /// SwiftDataに保存したチャット履歴を読み戻す
    @MainActor
    private func restoreChatHistoryIfNeeded() {
        if didLoadChatHistory {
            return
        }
        didLoadChatHistory = true

        let targetPack = currentPack ?? initialPack
        guard let pack = targetPack else {
            chatMessages = []
            return
        }
        currentPack = pack

        let storedData = pack.aiChatHistoryData
        if storedData.isEmpty {
            chatMessages = []
            return
        }
        do {
            let restored = try JSONDecoder().decode([AiChatMessage].self, from: storedData)
            if chatHistoryLimit < restored.count {
                chatMessages = Array(restored.suffix(chatHistoryLimit))
            } else {
                chatMessages = restored
            }
        } catch {
            chatMessages = []
        }
    }

    /// 送信済みドラフトを取り消して入力欄へ戻す
    @MainActor
    private func rollbackPendingDraftMessage() {
        guard let draft = pendingDraftMessage else {
            return
        }

        if let last = chatMessages.last, last.role == .user, last.content == draft {
            chatMessages.removeLast()
        } else if let index = chatMessages.lastIndex(where: { message in
            message.role == .user && message.content == draft
        }) {
            chatMessages.remove(at: index)
        }

        requirementText = draft
        requirementFocus.wrappedValue = true
        pendingDraftMessage = nil
    }

    /// チャット履歴を対象パックへ書き戻す
    @MainActor
    private func persistChatHistory() {
        guard let pack = currentPack else {
            return
        }
        do {
            let data = try JSONEncoder().encode(chatMessages)
            pack.aiChatHistoryData = data
        } catch {
            pack.aiChatHistoryData = Data()
        }
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("failed to save chat history: \(error)")
            #endif
        }
    }

    /// azuki-api経由でOpenAIにパック生成を依頼する
    private func generatePackWithOpenAI() {
        let currentMessages = chatMessages
        let latestUserMessage = currentMessages.last { message in
            message.role == .user
        }?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedMessage = latestUserMessage, trimmedMessage.isEmpty == false else {
            inlineGenerationFeedback = .failure(message: String(localized: "メッセージを入れてね"))
            return
        }

        let payload = buildChatPayload()
        if payload.isEmpty {
            inlineGenerationFeedback = .failure(message: String(localized: "メッセージを送信できませんでした"))
            return
        }

        let userId = creditStore.userId
        isGenerating = true
        Task {
            let cost = CHATGPT_GENERATION_CREDIT_COST
            var shouldRestoreCredits = false
            defer {
                Task {
                    await MainActor.run {
                        if shouldRestoreCredits {
                            rollbackPendingDraftMessage()
                            creditStore.add(credits: cost)
                        }
                        isGenerating = false
                    }
                }
            }

            let hasEnoughCredits = await ensureSufficientCreditsForGeneration(cost: cost)
            if hasEnoughCredits == false {
                await presentCreditShortageFeedback()
                await MainActor.run {
                    rollbackPendingDraftMessage()
                }
                return
            }

            do {
                try await MainActor.run {
                    try creditStore.consume(credits: cost)
                    shouldRestoreCredits = true
                }
            } catch {
                await presentCreditShortageFeedback()
                await MainActor.run {
                    rollbackPendingDraftMessage()
                }
                return
            }

            do {
                let response = try await requestPackFromServer(
                    userId: userId,
                    messages: payload,
                    canAttemptRecovery: true
                )
                shouldRestoreCredits = false
                do {
                    let result = try await MainActor.run { () -> (name: String, isNew: Bool) in
                        let applied = try applyPackResponse(from: response)

                        GALogger.log(.packlin_request(userId: userId,
                                                      requirement: trimmedMessage))
                        return (applied.pack.name, applied.isNewlyCreated)
                    }
                    await presentGenerationSuccess(packName: result.name, isNewlyCreated: result.isNew)
                    let assistantReply = response.memo
                    await appendAssistantMessage(assistantReply)
                    await MainActor.run {
                        pendingDraftMessage = nil
                    }
                } catch {
                    let message: String
                    if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                        message = description
                    } else {
                        message = error.localizedDescription
                    }
                    await MainActor.run {
                        rollbackPendingDraftMessage()
                    }
                    await presentGenerationFailure(message: message)
                }
            } catch let apiError as AzukiAPIError {
                await MainActor.run {
                    rollbackPendingDraftMessage()
                }
                switch apiError {
                case .insufficientCredits:
                    shouldRestoreCredits = false
                    await refreshCreditBalanceFromServer(showAlertOnFailure: false)
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
                await MainActor.run {
                    rollbackPendingDraftMessage()
                }
                let message = localized.errorDescription ?? localized.localizedDescription
                await presentGenerationFailure(message: message)
            } catch {
                await MainActor.run {
                    rollbackPendingDraftMessage()
                }
                await presentGenerationFailure(message:
                                                    String(localized: "チャッピーが忙しそうです。時間をおいて再度お試しください"))
            }
        }
    }

    /// 生成成功をユーザーへ伝える。画面表示中は画面内メッセージ、閉じていればローカル通知で知らせる
    /// - Parameters:
    ///   - packName: 生成に成功したパック名
    ///   - isNewlyCreated: 新規作成ならtrue、既存更新ならfalse
    private func presentGenerationSuccess(packName: String, isNewlyCreated: Bool) async {
        let viewVisible = await MainActor.run { isViewVisible }
        if viewVisible {
            await MainActor.run {
                let message: String
                if isNewlyCreated {
                    message = String(localized: "パック一覧に『\(packName)』を追加しました。パック一覧を見てください")
                } else {
                    message = String(localized: "『\(packName)』を更新しました。内容を確認してみましょう")
                }
                inlineGenerationFeedback = .success(message: message)
            }
            return
        }
        if isNewlyCreated {
            await LocalNotificationManager.shared.notifyPackGenerationSucceeded(packName: packName)
        } else {
            await LocalNotificationManager.shared.notifyPackGenerationUpdated(packName: packName)
        }
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
    ///   - messages: ユーザーとアシスタントのチャット履歴
    ///   - canAttemptRecovery: トークン再取得を試行できるかどうか（再帰呼び出し抑制用）
    /// - Returns: パックDTOと返信本文を含んだレスポンス
    private func requestPackFromServer(userId: String, messages: [AzukiApi.ChatMessagePayload], canAttemptRecovery: Bool) async throws -> PackJsonDTO {
        do {
            return try await AzukiApi.shared.generatePack(userId: userId,
                                                         messages: messages)
        } catch let apiError as AzukiAPIError {
            if canAttemptRecovery && shouldAttemptTokenRecovery(for: apiError) {
                let recovered = await recoverAccessTokenByVerifyingLatestTransactions()
                if recovered {
                    return try await requestPackFromServer(
                        userId: userId,
                        messages: messages,
                        canAttemptRecovery: false
                    )
                }
            }
            throw apiError
        }
    }

    /// APIへ送信するチャット履歴を整形する
    private func buildChatPayload() -> [AzukiApi.ChatMessagePayload] {
        chatMessages.map { message in
            AzukiApi.ChatMessagePayload(role: message.role.rawValue,
                                        content: message.content)
        }
    }

    /// サーバーから返ってきたパックDTOを現在のパックへ反映する
    @MainActor
    private func applyPackResponse(from dto: PackJsonDTO) throws -> (pack: M1Pack, isNewlyCreated: Bool) {
        if let existing = currentPack {
            try overwrite(pack: existing, with: dto)
            persistChatHistory()
            return (existing, false)
        }

        let importedPack = try createPack(from: dto)
        currentPack = importedPack
        persistChatHistory()
        return (importedPack, true)
    }

    /// 既存パックの中身をDTOでまるごと差し替える
    @MainActor
    private func overwrite(pack: M1Pack, with dto: PackJsonDTO) throws {
        modelContext.undoManager?.groupingBegin()
        defer {
            modelContext.undoManager?.groupingEnd()
        }

        pack.name = dto.name
        pack.memo = dto.memo

        let existingGroups = pack.child
        for group in existingGroups {
            let items = group.child
            for item in items {
                modelContext.delete(item)
            }
            modelContext.delete(group)
        }
        pack.child.removeAll()

        let groups = dto.groups.enumerated().sorted { left, right in
            let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
            let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
            return leftOrder < rightOrder
        }.map { $0.element }

        for (groupIndex, groupDTO) in groups.enumerated() {
            let group = M2Group(name: groupDTO.name,
                                memo: groupDTO.memo,
                                order: groupIndex * ORDER_SPARSE,
                                parent: pack)
            modelContext.insert(group)
            pack.child.append(group)

            let items = groupDTO.items.enumerated().sorted { left, right in
                let leftOrder = left.element.order ?? left.offset * ORDER_SPARSE
                let rightOrder = right.element.order ?? right.offset * ORDER_SPARSE
                return leftOrder < rightOrder
            }.map { $0.element }

            for (itemIndex, itemDTO) in items.enumerated() {
                let item = M3Item(name: itemDTO.name,
                                  memo: itemDTO.memo,
                                  check: itemDTO.check,
                                  stock: itemDTO.stock ?? 0,
                                  need: itemDTO.need,
                                  weight: itemDTO.weight,
                                  order: itemIndex * ORDER_SPARSE,
                                  parent: group)
                modelContext.insert(item)
                group.child.append(item)
            }
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
                    inlineGenerationFeedback = .failure(message: message)
                }
            }
            #if DEBUG
            print("[AzukiApi] failed to refresh balance: \(apiError)")
            #endif
        } catch {
            if showAlertOnFailure {
                await MainActor.run {
                    inlineGenerationFeedback = .failure(message: String(localized: "AI利用券の枚数が確認できません。通信環境をご確認ください。"))
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
                            alertState = .purchaseFailure(message: String(localized: "購入の承認待ちです。まだ課金されません。承認が完了すると自動で反映されます。"))
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
            localized: "購入の結果待ちです。まだ課金されません。確認が完了すると自動で反映されます。")


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
        /// クレジット保管上限に達している場合
        case purchaseLimitReached(max: Int)

        var id: String {
            switch self {
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
