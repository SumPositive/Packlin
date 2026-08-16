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

private struct ChappyRealtimeToolArguments: Decodable {
    let message: String
    let changes: [PackChangeDTO]
}

private struct ChappyRealtimeVoiceOption: Identifiable {
    let id: String
    let name: String
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
    @AppStorage(AppStorageKey.chappyVoiceIdentifier) private var voiceIdentifier = "marin"
    @AppStorage(AppStorageKey.chappyVoiceTempo) private var voiceTempo = 1.0
    @AppStorage(AppStorageKey.chappyVoicePitch) private var voicePitch = 1.0
    @StateObject private var speech = ChappySpeechService()
    @StateObject private var realtime = ChappyRealtimeService()
    @State private var messages: [ChappyConversationMessage] = []
    @State private var input = ""
    @State private var createdPack: M1Pack?
    @State private var appliedChanges: [AzukiApi.ChappyAppliedChange] = []
    @State private var isSending = false
    @State private var isVoiceConversationActive = false
    @State private var isPreparingVoiceConversation = false
    @State private var realtimeSessionId: String?
    @State private var realtimeSessionUserId: String?
    @State private var hasAttemptedAutomaticVoiceStart = false
    @State private var isConversationViewVisible = true
    @State private var isShowingPurchase = false
    @State private var purchaseReason: String?
    @State private var alertMessage: String?
    @State private var canRetryVoiceConversation = false
    @State private var retryRequestId: UUID?
    @State private var retryMessage: String?
    @FocusState private var isInputFocused: Bool

    private let voiceOptions = [
        ChappyRealtimeVoiceOption(id: "marin", name: "Marin"),
        ChappyRealtimeVoiceOption(id: "cedar", name: "Cedar"),
        ChappyRealtimeVoiceOption(id: "coral", name: "Coral"),
        ChappyRealtimeVoiceOption(id: "sage", name: "Sage"),
        ChappyRealtimeVoiceOption(id: "alloy", name: "Alloy")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                voiceConversationBar
                Divider()
                conversation
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
            }
            .task {
                guard hasAttemptedAutomaticVoiceStart == false else { return }
                hasAttemptedAutomaticVoiceStart = true
                // 端末残高が不足する場合だけサーバーと同期して開始遅延を抑える
                if creditStore.credits < CHAPPY_REALTIME_RESPONSE_MIN_CREDIT_COST {
                    await refreshCreditBalance()
                }
                await startVoiceConversation()
            }
            .onChange(of: speech.transcript) { _, transcript in
                // 認識途中の発話内容を画面にも反映する
                input = transcript
            }
            .onAppear {
                isConversationViewVisible = true
                normalizeVoiceSettings()
            }
            .onDisappear {
                isConversationViewVisible = false
                isPreparingVoiceConversation = false
                endVoiceConversation()
            }
            .sheet(isPresented: $isShowingPurchase, onDismiss: {
                purchaseReason = nil
            }) {
                ChappyCreditPurchaseView(reason: purchaseReason)
                    .presentationDetents([.medium])
            }
            .alert(String(localized: "chappy", defaultValue: "チャッピー"), isPresented: Binding(
                get: { alertMessage != nil },
                set: {
                    if $0 == false {
                        alertMessage = nil
                        canRetryVoiceConversation = false
                    }
                }
            )) {
                if canRetryVoiceConversation {
                    Button(String(localized: "retry", defaultValue: "リトライ")) {
                        canRetryVoiceConversation = false
                        alertMessage = nil
                        Task { await startVoiceConversation() }
                    }
                    Button(String(localized: "cancel", defaultValue: "キャンセル"), role: .cancel) {
                        canRetryVoiceConversation = false
                    }
                } else {
                    Button("OK", role: .cancel) {}
                }
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
                if isVoiceConversationActive, realtime.isListening {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                } else if isPreparingVoiceConversation || realtime.isProcessing {
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
        if realtime.isSpeaking {
            return String(localized: "chappy.voice.speaking", defaultValue: "チャッピーが話しています")
        }
        if realtime.isListening {
            return String(localized: "chappy.voice.listening", defaultValue: "聞いています")
        }
        if realtime.isProcessing {
            return String(localized: "chappy.thinking", defaultValue: "考えています")
        }
        return String(localized: "chappy.voice.conversation.stop", defaultValue: "会話モードを終了")
    }

    private var statusBar: some View {
        // 新規作成後は会話中に保持しているパック名へ表示を切り替える
        let packName = currentPack?.name ?? ""
        return HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text(packName.isEmpty == false
                 ? packName
                 : String(localized: "chappy.new.pack", defaultValue: "新しいパック"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button {
                purchaseReason = nil
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
                    voiceSettings
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
                // 最初の挨拶では設定欄を残し、会話が進んだら最新発言へ送る
                if 1 < messages.count, let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var voiceSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "chappy.voice.settings", defaultValue: "会話・音声設定"), systemImage: "waveform")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "chappy.response.tone", defaultValue: "応答トーン"), systemImage: "text.bubble")
                    .font(.subheadline)
                Picker(String(localized: "chappy.response.tone", defaultValue: "応答トーン"), selection: $tone) {
                    ForEach(ChappyResponseTone.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            settingPickerRow(
                title: String(localized: "chappy.voice.type", defaultValue: "声の種類"),
                systemImage: "person.crop.circle"
            ) {
                Picker(String(localized: "chappy.voice.type", defaultValue: "声の種類"), selection: $voiceIdentifier) {
                    ForEach(voiceOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }

            voiceSliderRow(
                title: String(localized: "chappy.voice.tempo", defaultValue: "話す速さ"),
                systemImage: "speedometer",
                value: $voiceTempo,
                range: 0.75...1.25
            )
            voiceSliderRow(
                title: String(localized: "chappy.voice.pitch", defaultValue: "声の高さ"),
                systemImage: "tuningfork",
                value: $voicePitch,
                range: 0.8...1.2
            )
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private func settingPickerRow<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
            Spacer(minLength: 8)
            content()
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }

    private func voiceSliderRow(
        title: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.2f×", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.05)
        }
    }

    private func normalizeVoiceSettings() {
        // 保存値とRealtime音声を照合し、安全な範囲へ戻す
        voiceTempo = min(1.25, max(0.75, voiceTempo))
        voicePitch = min(1.2, max(0.8, voicePitch))
        if voiceOptions.contains(where: { $0.id == voiceIdentifier }) == false {
            voiceIdentifier = "marin"
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
                    speak(message.content)
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

    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isSending == false else { return }
        guard CHAPPY_CONVERSATION_MAX_CREDIT_COST <= creditStore.credits else {
            endVoiceConversation()
            showCreditPurchase()
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
            // 差分ツールが既存要素を特定できるようID付きの現在状態を送る
            let basePackDTO = await MainActor.run { currentPack?.conversationRepresentation() }
            let selectedTone = await MainActor.run { tone }
            do {
                let result = try await AzukiApi.shared.converseWithChappy(
                    userId: creditStore.regenerateUserIdIfNeeded(),
                    requestId: requestId,
                    message: trimmed,
                    history: historyItems,
                    appliedChanges: appliedChanges,
                    basePack: basePackDTO,
                    tone: selectedTone,
                    languageCode: preferredLanguageCode()
                )
                creditStore.overwriteFromServer(credits: result.balance)
                let responseMessage: String
                if result.changes.isEmpty == false {
                    // 差分全体を1回のUndo操作として即時反映する
                    let wasCreated = currentPack == nil
                    let appliedPack: M1Pack
                    do {
                        appliedPack = try applyChanges(result.changes)
                    } catch {
                        // 検証済み差分を適用できない場合は再送せず、現在データを維持する
                        isSending = false
                        retryRequestId = nil
                        retryMessage = nil
                        let invalidResponse = AzukiAPIError.invalidResponse.localizedDescription
                        messages.append(ChappyConversationMessage(role: .assistant, content: invalidResponse, chargedCredits: nil))
                        alertMessage = invalidResponse
                        return
                    }
                    let packName = appliedPack.name
                    // 既存パックでは定型の完了文を付けず、具体的な変更内容だけを残す
                    let changeSummary = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
                    if wasCreated {
                        let completionMessage = String(format: String(localized: "chappy.pack.created", defaultValue: "「%@」を作成しました"), packName)
                        responseMessage = changeSummary.isEmpty
                            ? completionMessage
                            : "\(completionMessage)\n\n\(changeSummary)"
                    } else {
                        responseMessage = changeSummary
                    }
                    // 適用済みの依頼と結果を記録し、後の変更で以前の内容へ戻ることを防ぐ
                    appliedChanges.append(AzukiApi.ChappyAppliedChange(
                        request: String(trimmed.prefix(600)),
                        result: String(changeSummary.prefix(600))
                    ))
                    if 12 < appliedChanges.count {
                        appliedChanges.removeFirst(appliedChanges.count - 12)
                    }
                } else {
                    responseMessage = result.message
                }
                messages.append(ChappyConversationMessage(
                    role: .assistant,
                    content: responseMessage,
                    chargedCredits: result.chargedCredits
                ))
                input = ""
                retryRequestId = nil
                retryMessage = nil
                GALogger.log(.feature_use(name: "ai_conversation", source: basePack == nil ? "pack_add" : "group_list", detail: "success"))
                isSending = false
            } catch {
                if case AzukiAPIError.noPackChanges = error {
                    // 変更なしは通信失敗にせず、返金後に具体的な指示を聞き直す
                    await refreshCreditBalance()
                    isSending = false
                    retryRequestId = nil
                    retryMessage = nil
                    let noChangesMessage = error.localizedDescription
                    messages.append(ChappyConversationMessage(role: .assistant, content: noChangesMessage, chargedCredits: nil))
                    return
                }
                // 同じIDで再送できるよう保持し、応答消失時の二重課金を防ぐ
                retryRequestId = requestId
                retryMessage = trimmed
                await refreshCreditBalance()
                isSending = false
                alertMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func startVoiceConversation() async {
        guard isVoiceConversationActive == false, isPreparingVoiceConversation == false else { return }
        normalizeVoiceSettings()
        guard CHAPPY_REALTIME_RESPONSE_MIN_CREDIT_COST <= creditStore.credits else {
            showCreditPurchase()
            return
        }
        isPreparingVoiceConversation = true
        configureRealtimeCallbacks()
        isInputFocused = false
        input = ""
        speech.stopListening()
        speech.stopSpeaking()
        let userId = creditStore.regenerateUserIdIfNeeded()
        let requestId = UUID()
        let historyItems = Array(messages.suffix(8)).map { message in
            AzukiApi.ChappyHistoryItem(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
        let basePackDTO = currentPack?.conversationRepresentation()
        let selectedTone = tone
        let selectedVoice = voiceIdentifier
        let selectedTempo = voiceTempo
        let selectedPitch = voicePitch
        let languageCode = preferredLanguageCode()
        do {
            try await realtime.start { offerSdp in
                let result = try await AzukiApi.shared.startChappyRealtimeSession(
                    userId: userId,
                    requestId: requestId,
                    offerSdp: offerSdp,
                    history: historyItems,
                    appliedChanges: appliedChanges,
                    basePack: basePackDTO,
                    tone: selectedTone,
                    languageCode: languageCode,
                    voice: selectedVoice,
                    voiceTempo: selectedTempo,
                    voicePitch: selectedPitch
                )
                // 応答前の仮押さえ残高は表示せず、精算後に実消費だけを反映する
                realtimeSessionId = result.sessionId
                realtimeSessionUserId = userId
                return result.sdp
            }
            try await AzukiApi.shared.markChappyRealtimeSessionReady(
                userId: userId,
                sessionId: requestId.uuidString
            )
            guard isConversationViewVisible else {
                endVoiceConversation()
                return
            }
            isVoiceConversationActive = true
            isPreparingVoiceConversation = false
            GALogger.log(.feature_use(name: "ai_voice_conversation", source: basePack == nil ? "pack_add" : "group_list", detail: "start"))
        } catch {
            finishRealtimeSessionOnServer()
            realtime.stop()
            isVoiceConversationActive = false
            isPreparingVoiceConversation = false
            await refreshCreditBalance()
            if let realtimeError = error as? ChappyRealtimeError,
               case .microphonePermissionRequired = realtimeError {
                canRetryVoiceConversation = false
                alertMessage = error.localizedDescription
            } else {
                canRetryVoiceConversation = true
                alertMessage = String(localized: "chappy.voice.error.retry", defaultValue: "通信に失敗しました。リトライしますか")
            }
        }
    }

    private func configureRealtimeCallbacks() {
        realtime.onUserTranscript = { transcript in
            if isVoiceEndCommand(transcript) {
                endVoiceConversation()
                return
            }
            input = transcript
            messages.append(ChappyConversationMessage(role: .user, content: transcript, chargedCredits: nil))
        }
        realtime.onAssistantTranscript = { transcript in
            messages.append(ChappyConversationMessage(role: .assistant, content: transcript, chargedCredits: nil))
        }
        realtime.onToolCall = { toolCall in
            handleRealtimeToolCall(toolCall)
        }
        realtime.onResponseCompleted = {
            Task {
                // サイドバンド側の精算がNeonへ反映されてから残高を同期する
                let balanceBeforeResponse = creditStore.credits
                try? await Task.sleep(nanoseconds: 800_000_000)
                await refreshCreditBalance()
                let chargedCredits = max(0, balanceBeforeResponse - creditStore.credits)
                recordLatestVoiceCharge(chargedCredits)
            }
        }
        realtime.onInsufficientCredits = {
            endVoiceConversation()
            showCreditPurchase()
        }
        realtime.onSessionEnded = {
            // 時間上限や相手側切断でも会話中表示を確実に解除する
            finishRealtimeSessionOnServer()
            isVoiceConversationActive = false
            isPreparingVoiceConversation = false
            GALogger.log(.feature_use(name: "ai_voice_conversation", source: basePack == nil ? "pack_add" : "group_list", detail: "remote_stop"))
        }
        realtime.onError = { message in
            endVoiceConversation()
            canRetryVoiceConversation = true
            alertMessage = message
        }
    }

    private func handleRealtimeToolCall(_ toolCall: ChappyRealtimeService.ToolCall) {
        guard toolCall.name == "apply_pack_changes",
              let data = toolCall.arguments.data(using: .utf8),
              let arguments = try? JSONDecoder().decode(ChappyRealtimeToolArguments.self, from: data),
              arguments.changes.isEmpty == false else {
            realtime.sendToolOutput(callId: toolCall.callId, success: false, currentPack: currentPack?.conversationRepresentation())
            return
        }
        do {
            // Realtimeの差分も1応答単位でUndoできるよう既存の適用経路へ通す
            _ = try applyChanges(arguments.changes)
            let request = messages.last(where: { $0.role == .user })?.content ?? ""
            appliedChanges.append(AzukiApi.ChappyAppliedChange(
                request: String(request.prefix(600)),
                result: String(appliedChangeSummary(arguments.changes).prefix(600))
            ))
            if 12 < appliedChanges.count {
                appliedChanges.removeFirst(appliedChanges.count - 12)
            }
            realtime.sendToolOutput(
                callId: toolCall.callId,
                success: true,
                currentPack: currentPack?.conversationRepresentation(),
                appliedOperations: arguments.changes.map(\.action.rawValue)
            )
        } catch {
            // 適用失敗時は現在データを維持し、AIへ再提案を求める
            realtime.sendToolOutput(callId: toolCall.callId, success: false, currentPack: currentPack?.conversationRepresentation())
        }
    }

    private func speak(_ message: String) {
        // 履歴の試聴は端末音声を使い、Realtime専用の音声名とは分離する
        speech.speak(
            message,
            languageCode: preferredLanguageCode(),
            voiceIdentifier: nil,
            tempo: voiceTempo,
            pitch: voicePitch,
            onFinished: nil
        )
    }

    private func showCreditPurchase() {
        let message = String(
            localized: "chappy.credits.insufficient.guide",
            defaultValue: "クレジットが不足したため会話を終了しました。続けるにはクレジットを購入してください"
        )
        // 不足理由を履歴と音声で伝え、購入シートにも同じ案内を表示する
        if messages.last?.content != message {
            messages.append(ChappyConversationMessage(role: .assistant, content: message, chargedCredits: nil))
        }
        speak(message)
        canRetryVoiceConversation = false
        alertMessage = nil
        purchaseReason = message
        isShowingPurchase = true
    }

    private func recordLatestVoiceCharge(_ chargedCredits: Int) {
        guard 0 < chargedCredits,
              let index = messages.lastIndex(where: { $0.role == .assistant && $0.chargedCredits == nil }) else {
            return
        }
        let message = messages[index]
        // 音声応答にも実精算額を表示し、仮押さえと利用額を混同させない
        messages[index] = ChappyConversationMessage(
            role: message.role,
            content: message.content,
            chargedCredits: chargedCredits
        )
    }

    private func endVoiceConversation() {
        guard isVoiceConversationActive
                || isPreparingVoiceConversation
                || realtime.connectionState != .disconnected else { return }
        isVoiceConversationActive = false
        isPreparingVoiceConversation = false
        finishRealtimeSessionOnServer()
        realtime.stop()
        GALogger.log(.feature_use(name: "ai_voice_conversation", source: basePack == nil ? "pack_add" : "group_list", detail: "stop"))
    }

    private func finishRealtimeSessionOnServer() {
        guard let sessionId = realtimeSessionId,
              let userId = realtimeSessionUserId else { return }
        // 多重通知を防ぐため識別子を先に消し、終了APIは画面を待たせず送信する
        realtimeSessionId = nil
        realtimeSessionUserId = nil
        Task {
            try? await AzukiApi.shared.endChappyRealtimeSession(userId: userId, sessionId: sessionId)
            // 終了時の未使用予約返金を端末表示へ反映する
            await refreshCreditBalance()
        }
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

    private var currentPack: M1Pack? {
        basePack ?? createdPack
    }

    private func appliedChangeSummary(_ changes: [PackChangeDTO]) -> String {
        // AIの自己申告ではなく、実際に適用した操作と名称を会話履歴へ残す
        changes.map { change in
            [change.action.rawValue, change.name, change.targetId]
                .compactMap { $0 }
                .joined(separator: ":")
        }
        .joined(separator: ",")
    }

    private func applyChanges(_ changes: [PackChangeDTO]) throws -> M1Pack {
        let insertionIndex = insertionPosition == .head ? 0 : sortedPacks.count
        let newOrder = sparseOrderForInsertion(items: sortedPacks, index: insertionIndex) {
            normalizeSparseOrders(sortedPacks)
        }
        var appliedPack: M1Pack?
        try history.perform(context: modelContext) {
            // 全量置換せず、AIが指定したプロパティと行だけを変更する
            appliedPack = try PackImporter.applyChanges(
                changes,
                to: currentPack,
                in: modelContext,
                newPackOrder: newOrder
            )
            // 保存まで成功した変更だけをRealtimeへ成功として返す
            try modelContext.save()
        }
        guard let appliedPack else { throw PackChangeApplicationError.invalidChanges }
        // 新規作成後も同じ会話内で続けて変更できるよう対象を保持する
        if basePack == nil {
            createdPack = appliedPack
        }
        GALogger.log(.feature_use(name: "ai_apply", source: basePack == nil ? "pack_add" : "group_list", detail: "pack"))
        return appliedPack
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
