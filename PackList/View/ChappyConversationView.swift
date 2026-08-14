//  チャッピー会話画面
//  テキスト・音声相談、パック提案の確認と適用をまとめる
//

import SwiftData
import SwiftUI

private struct ChappyConversationMessage: Identifiable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
    let chargedCredits: Int?
}

struct ChappyConversationView: View {
    let basePack: M1Pack?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var history: UndoStackService
    @EnvironmentObject private var creditStore: CreditStore
    @Query(sort: [SortDescriptor(\M1Pack.order)]) private var sortedPacks: [M1Pack]

    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    @AppStorage(AppStorageKey.chappyResponseTone) private var tone: ChappyResponseTone = .gentle
    @StateObject private var speech = ChappySpeechService()
    @State private var messages: [ChappyConversationMessage] = []
    @State private var input = ""
    @State private var proposedPack: PackJsonDTO?
    @State private var isSending = false
    @State private var isVoiceConversationActive = false
    @State private var isPreparingVoiceConversation = false
    @State private var hasAttemptedAutomaticVoiceStart = false
    @State private var isConversationViewVisible = true
    @State private var isShowingPurchase = false
    @State private var alertMessage: String?
    @State private var retryRequestId: UUID?
    @State private var retryMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                voiceConversationBar
                Divider()
                conversation
                if proposedPack != nil {
                    proposalBar
                }
                if isVoiceConversationActive == false, isPreparingVoiceConversation == false {
                    Divider()
                    composer
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "chappy.conversation.title", defaultValue: "チャッピー(AI)と会話"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        endVoiceConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(String(localized: "chappy.response.tone", defaultValue: "応答トーン"), selection: $tone) {
                            ForEach(ChappyResponseTone.allCases) { option in
                                Text(option.localizedName).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                }
            }
            .task {
                guard hasAttemptedAutomaticVoiceStart == false else { return }
                hasAttemptedAutomaticVoiceStart = true
                // 端末残高が不足する場合だけサーバーと同期して開始遅延を抑える
                if creditStore.credits < CHAPPY_CONVERSATION_MAX_CREDIT_COST {
                    await refreshCreditBalance()
                }
                await startVoiceConversation()
            }
            .onChange(of: speech.transcript) { _, transcript in
                // 認識途中の発話内容を画面にも反映する
                input = transcript
            }
            .onChange(of: speech.errorMessage) { _, errorMessage in
                if errorMessage != nil, isVoiceConversationActive {
                    // 音声認識の異常時は待機中のまま残さない
                    endVoiceConversation()
                }
            }
            .onAppear {
                isConversationViewVisible = true
            }
            .onDisappear {
                isConversationViewVisible = false
                isPreparingVoiceConversation = false
                endVoiceConversation()
            }
            .sheet(isPresented: $isShowingPurchase) {
                ChappyCreditPurchaseView()
                    .presentationDetents([.medium])
            }
            .alert(String(localized: "chappy", defaultValue: "チャッピー"), isPresented: Binding(
                get: { alertMessage != nil },
                set: { if $0 == false { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var voiceConversationBar: some View {
        Button {
            if isVoiceConversationActive {
                endVoiceConversation()
            } else {
                Task {
                    await startVoiceConversation()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isVoiceConversationActive ? "stop.circle.fill" : "waveform.circle.fill")
                Text(voiceConversationStatusText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if isVoiceConversationActive, speech.isListening {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                } else if isPreparingVoiceConversation || (isVoiceConversationActive && isSending) {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isVoiceConversationActive ? .red : COLOR_ADD_ACTION)
        .disabled(isPreparingVoiceConversation || (isSending && isVoiceConversationActive == false))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var voiceConversationStatusText: String {
        if isPreparingVoiceConversation {
            return String(localized: "chappy.voice.preparing", defaultValue: "会話を準備しています")
        }
        if isVoiceConversationActive == false {
            return String(localized: "chappy.voice.conversation.start", defaultValue: "会話モードを開始")
        }
        if speech.isSpeaking {
            return String(localized: "chappy.voice.speaking", defaultValue: "チャッピーが話しています")
        }
        if speech.isListening {
            return String(localized: "chappy.voice.listening", defaultValue: "聞いています")
        }
        if isSending {
            return String(localized: "chappy.thinking", defaultValue: "考えています")
        }
        return String(localized: "chappy.voice.conversation.stop", defaultValue: "会話モードを終了")
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text(basePack?.name.isEmpty == false
                 ? basePack?.name ?? ""
                 : String(localized: "chappy.new.pack", defaultValue: "新しいパック"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button {
                isShowingPurchase = true
            } label: {
                Label("\(creditStore.credits)", systemImage: "plus.circle")
                    .font(.subheadline.monospacedDigit())
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        Text(String(localized: "chappy.conversation.empty", defaultValue: "持ち物の作成、変更、確認について話しかけてください"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                            .padding(.horizontal, 32)
                    }
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if isSending {
                        HStack {
                            ProgressView()
                            Text(String(localized: "chappy.thinking", defaultValue: "考えています"))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: ChappyConversationMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                if let chargedCredits = message.chargedCredits {
                    Text(String(format: String(localized: "chappy.credits.used", defaultValue: "%lldクレジット使用"), Int64(chargedCredits)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if message.role == .assistant {
                Button {
                    speech.speak(message.content, languageCode: preferredLanguageCode())
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.plain)
                .disabled(isVoiceConversationActive)
                Spacer(minLength: 24)
            }
        }
        .padding(.horizontal, 16)
    }

    private var proposalBar: some View {
        HStack {
            Image(systemName: "shippingbox")
                .foregroundStyle(COLOR_ADD_ACTION)
            Text(String(localized: "chappy.pack.proposal.ready", defaultValue: "パックの変更案があります"))
                .font(.subheadline)
            Spacer()
            Button {
                applyProposal()
            } label: {
                Text(String(localized: "chappy.apply.proposal", defaultValue: "提案を適用"))
            }
            .buttonStyle(.borderedProminent)
            .tint(COLOR_ADD_ACTION)
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let speechError = speech.errorMessage {
                Text(speechError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    Task {
                        if speech.isListening {
                            speech.stopListening()
                        } else {
                            speech.transcript = input
                            await speech.startListening(initialText: input)
                        }
                    }
                } label: {
                    Image(systemName: speech.isListening ? "stop.circle.fill" : "mic")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .tint(speech.isListening ? .red : .accentColor)
                .accessibilityLabel(String(localized: "chappy.voice.input", defaultValue: "音声入力"))

                TextField(String(localized: "chappy.message.placeholder", defaultValue: "持ち物について相談する"), text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: input) { _, newValue in
                        if 1000 < newValue.count {
                            input = String(newValue.prefix(1000))
                        }
                        if isVoiceConversationActive == false, retryMessage != newValue {
                            retryRequestId = nil
                            retryMessage = nil
                        }
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || isVoiceConversationActive || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(String(localized: "send", defaultValue: "送信"))
            }
        }
        .disabled(isVoiceConversationActive)
        .opacity(isVoiceConversationActive ? 0.55 : 1)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private func sendMessage(_ voiceMessage: String? = nil) {
        let trimmed = (voiceMessage ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isSending == false else { return }
        guard CHAPPY_CONVERSATION_MAX_CREDIT_COST <= creditStore.credits else {
            endVoiceConversation()
            alertMessage = String(localized: "chappy.credits.insufficient", defaultValue: "クレジットが不足しています")
            isShowingPurchase = true
            return
        }

        let isRetry = retryRequestId != nil && retryMessage == trimmed
        let requestId = isRetry ? retryRequestId ?? UUID() : UUID()
        // 再送時は直前に表示済みの同一ユーザー発言を履歴から外して重複を防ぐ
        var historyMessages = messages
        if isRetry,
           historyMessages.last?.role == .user,
           historyMessages.last?.content == trimmed {
            historyMessages.removeLast()
        }
        let historyItems = Array(historyMessages.suffix(8)).map { message in
            AzukiApi.ChappyHistoryItem(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
        if isRetry == false {
            retryRequestId = nil
            retryMessage = nil
            messages.append(ChappyConversationMessage(role: .user, content: trimmed, chargedCredits: nil))
        }
        isSending = true
        isInputFocused = false
        speech.stopListening()

        Task {
            let basePackDTO = await MainActor.run { basePack?.exportRepresentation() }
            let selectedTone = await MainActor.run { tone }
            do {
                let result = try await AzukiApi.shared.converseWithChappy(
                    userId: creditStore.regenerateUserIdIfNeeded(),
                    requestId: requestId,
                    message: trimmed,
                    history: historyItems,
                    basePack: basePackDTO,
                    tone: selectedTone,
                    languageCode: preferredLanguageCode()
                )
                creditStore.overwriteFromServer(credits: result.balance)
                messages.append(ChappyConversationMessage(
                    role: .assistant,
                    content: result.message,
                    chargedCredits: result.chargedCredits
                ))
                proposedPack = result.proposedPack
                input = ""
                retryRequestId = nil
                retryMessage = nil
                GALogger.log(.feature_use(name: "ai_conversation", source: basePack == nil ? "pack_add" : "group_list", detail: "success"))
                isSending = false
                if isVoiceConversationActive {
                    speakThenListen(result.message)
                }
            } catch {
                // 同じIDで再送できるよう保持し、応答消失時の二重課金を防ぐ
                retryRequestId = requestId
                retryMessage = trimmed
                await refreshCreditBalance()
                isSending = false
                if isVoiceConversationActive {
                    let retryGuide = String(localized: "chappy.voice.error.retry", defaultValue: "通信に失敗しました。リトライしますか")
                    messages.append(ChappyConversationMessage(role: .assistant, content: retryGuide, chargedCredits: nil))
                    speakThenListen(retryGuide)
                } else {
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func startVoiceConversation() async {
        guard isVoiceConversationActive == false, isPreparingVoiceConversation == false else { return }
        guard CHAPPY_CONVERSATION_MAX_CREDIT_COST <= creditStore.credits else {
            alertMessage = String(localized: "chappy.credits.insufficient", defaultValue: "クレジットが不足しています")
            isShowingPurchase = true
            return
        }
        isPreparingVoiceConversation = true
        let isPrepared = await speech.prepareForConversation()
        isPreparingVoiceConversation = false
        // 権限確認中に画面を閉じた場合は会話を開始しない
        guard isPrepared, isConversationViewVisible else { return }

        isInputFocused = false
        input = ""
        speech.transcript = ""
        speech.errorMessage = nil
        isVoiceConversationActive = true
        let greeting = basePack == nil
            ? String(localized: "chappy.voice.greeting.create", defaultValue: "どのようなパックを作成しますか")
            : String(localized: "chappy.voice.greeting.edit", defaultValue: "このパックについて、どのようなことをしますか")
        messages.append(ChappyConversationMessage(role: .assistant, content: greeting, chargedCredits: nil))
        speakThenListen(greeting)
        GALogger.log(.feature_use(name: "ai_voice_conversation", source: basePack == nil ? "pack_add" : "group_list", detail: "start"))
    }

    private func speakThenListen(_ message: String) {
        guard isVoiceConversationActive else { return }
        speech.speak(message, languageCode: preferredLanguageCode()) {
            guard isVoiceConversationActive else { return }
            beginAutomaticListening()
        }
    }

    private func beginAutomaticListening() {
        guard isVoiceConversationActive, isSending == false else { return }
        input = ""
        speech.transcript = ""
        Task {
            await speech.startListening(initialText: "") { recognizedText in
                guard isVoiceConversationActive else { return }
                if isVoiceEndCommand(recognizedText) {
                    let closing = String(localized: "chappy.voice.conversation.ended", defaultValue: "会話モードを終了しました")
                    messages.append(ChappyConversationMessage(role: .assistant, content: closing, chargedCredits: nil))
                    endVoiceConversation()
                    return
                }
                input = recognizedText
                sendMessage(recognizedText)
            }
            if isVoiceConversationActive, speech.isListening == false, speech.errorMessage != nil {
                // 権限不足や非対応時は自動会話を止め、画面内の案内を表示する
                endVoiceConversation()
            }
        }
    }

    private func endVoiceConversation() {
        guard isVoiceConversationActive || speech.isListening || speech.isSpeaking else { return }
        isVoiceConversationActive = false
        speech.stopListening()
        speech.stopSpeaking()
        GALogger.log(.feature_use(name: "ai_voice_conversation", source: basePack == nil ? "pack_add" : "group_list", detail: "stop"))
    }

    private func isVoiceEndCommand(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // 短い終了指示だけを扱い、通常の会話に含まれる語では終了しない
        let commands: Set<String> = [
            "終了", "おしまい", "会話を終了", "会話終了",
            "stop", "stop conversation", "end conversation",
            "beenden", "gespräch beenden", "terminar", "terminar conversación",
            "arrêter", "terminer la conversation", "fine", "termina conversazione",
            "종료", "대화 종료", "結束", "結束對話"
        ]
        return commands.contains(normalized)
    }

    private func applyProposal() {
        guard let proposedPack else { return }
        history.perform(context: modelContext) {
            if let basePack {
                // 既存パックはIDと並び順を保ったまま内容だけ入れ替える
                PackImporter.overwrite(pack: basePack, with: proposedPack, in: modelContext)
            } else {
                let insertionIndex = insertionPosition == .head ? 0 : sortedPacks.count
                let newOrder = sparseOrderForInsertion(items: sortedPacks, index: insertionIndex) {
                    normalizeSparseOrders(sortedPacks)
                }
                PackImporter.insertPack(from: proposedPack, into: modelContext, order: newOrder)
            }
        }
        self.proposedPack = nil
        messages.append(ChappyConversationMessage(
            role: .assistant,
            content: String(localized: "chappy.proposal.applied", defaultValue: "提案をパックへ反映しました"),
            chargedCredits: nil
        ))
        GALogger.log(.feature_use(name: "ai_apply", source: basePack == nil ? "pack_add" : "group_list", detail: "pack"))
    }

    private func refreshCreditBalance() async {
        do {
            let status = try await AzukiApi.shared.fetchCreditStatus(userId: creditStore.regenerateUserIdIfNeeded())
            creditStore.overwriteFromServer(credits: status.balance)
        } catch {
            // オフライン時は端末に保存した残高表示を維持する
        }
    }

    private func preferredLanguageCode() -> String? {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        if preferred.lowercased().hasPrefix("zh-hant") {
            return "zh-Hant"
        }
        return Locale(identifier: preferred).language.languageCode?.identifier
    }
}
