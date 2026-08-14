//  チャッピー音声サービス
//  端末内の音声認識と読み上げをまとめる
//

import AVFoundation
import Combine
import Speech

@MainActor
final class ChappySpeechService: NSObject, ObservableObject {
    /// 端末で選択できる読み上げ音声
    struct VoiceOption: Identifiable {
        let id: String
        let name: String
    }

    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var isOnDeviceRecognitionAvailable = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionCompletion: ((String) -> Void)?
    private var speechCompletion: (() -> Void)?
    private var activeUtterance: AVSpeechUtterance?
    private var silenceTask: Task<Void, Never>?
    private var hasInputTap = false
    private var isConversationPrepared = false

    override init() {
        super.init()
        synthesizer.delegate = self
        refreshAvailability()
    }

    /// 現在の言語で端末内認識が利用できるかを更新する
    func refreshAvailability() {
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        isOnDeviceRecognitionAvailable = recognizer?.supportsOnDeviceRecognition == true
    }

    /// 会話開始前に音声認識とマイクを準備する
    func prepareForConversation() async -> Bool {
        if isConversationPrepared {
            return true
        }
        errorMessage = nil
        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = String(localized: "chappy.voice.permission.required", defaultValue: "音声入力を使うには音声認識の許可が必要です")
            return false
        }
        let microphoneGranted = await requestMicrophoneAuthorization()
        guard microphoneGranted else {
            errorMessage = String(localized: "chappy.microphone.permission.required", defaultValue: "音声入力を使うにはマイクの許可が必要です")
            return false
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.supportsOnDeviceRecognition else {
            errorMessage = String(localized: "chappy.voice.on.device.unavailable", defaultValue: "この端末と言語では端末内音声認識を利用できません")
            return false
        }
        isOnDeviceRecognitionAvailable = true
        isConversationPrepared = true
        return true
    }

    /// 権限確認後に端末内音声認識を開始する
    func startListening(initialText: String? = nil, onFinal: ((String) -> Void)? = nil) async {
        let existingText = initialText ?? transcript
        stopListening()
        errorMessage = nil
        transcript = existingText
        recognitionCompletion = onFinal

        if isConversationPrepared == false {
            guard await prepareForConversation() else { return }
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.supportsOnDeviceRecognition else {
            errorMessage = String(localized: "chappy.voice.on.device.unavailable", defaultValue: "この端末と言語では端末内音声認識を利用できません")
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            // 音声データを外部処理へ送らず端末内認識だけを許可する
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInputTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let recognizedText = result.bestTranscription.formattedString
                        // 既存入力を残したまま、その後ろへ音声認識結果を追加する
                        self.transcript = existingText.isEmpty ? recognizedText : "\(existingText) \(recognizedText)"
                        if result.isFinal {
                            self.finishListening(submit: true)
                        } else if recognizedText.isEmpty == false {
                            // 発話後の無音を検出してタップなしで確定する
                            self.scheduleSilenceFinish()
                        }
                    }
                    if error != nil, self.isListening {
                        self.errorMessage = String(localized: "chappy.voice.start.failed", defaultValue: "音声入力を開始できませんでした")
                        self.stopListening()
                    }
                }
            }
        } catch {
            stopListening()
            errorMessage = String(localized: "chappy.voice.start.failed", defaultValue: "音声入力を開始できませんでした")
        }
    }

    /// 録音と認識タスクを終了する
    func stopListening() {
        recognitionCompletion = nil
        stopRecognitionResources()
    }

    /// 現在の言語で利用できる読み上げ音声を返す
    func availableVoices(languageCode: String?) -> [VoiceOption] {
        let requestedLanguage = Locale(identifier: languageCode ?? Locale.current.identifier)
            .language.languageCode?.identifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let voiceLanguage = Locale(identifier: voice.language).language.languageCode?.identifier
                return requestedLanguage == nil || voiceLanguage == requestedLanguage
            }
            .map { VoiceOption(id: $0.identifier, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// チャッピーの返答を選択された声質で読み上げる
    func speak(
        _ text: String,
        languageCode: String?,
        voiceIdentifier: String? = nil,
        tempo: Double = 1,
        pitch: Double = 1,
        onFinished: (() -> Void)? = nil
    ) {
        stopListening()
        stopSpeaking()
        errorMessage = nil

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try audioSession.setActive(true)
        } catch {
            // 読み上げ自体は音声セッション設定なしでも続行する
        }

        speechCompletion = onFinished
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        let selectedVoice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        let requestedLanguage = Locale(identifier: languageCode ?? Locale.current.identifier)
            .language.languageCode?.identifier
        let selectedLanguage = selectedVoice.flatMap {
            Locale(identifier: $0.language).language.languageCode?.identifier
        }
        // 保存済み音声の言語が現在と異なる場合は端末の自動選択へ戻す
        utterance.voice = selectedLanguage == requestedLanguage
            ? selectedVoice
            : AVSpeechSynthesisVoice(language: languageCode)
        // 端末が許容する範囲へ収め、保存値の破損でも読み上げを継続する
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(tempo))
        )
        utterance.pitchMultiplier = min(2, max(0.5, Float(pitch)))
        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// 読み上げと後続処理を中止する
    func stopSpeaking() {
        speechCompletion = nil
        activeUtterance = nil
        isSpeaking = false
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func scheduleSilenceFinish() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard Task.isCancelled == false else { return }
            self?.finishListening(submit: true)
        }
    }

    private func finishListening(submit: Bool) {
        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let completion = recognitionCompletion
        recognitionCompletion = nil
        stopRecognitionResources()
        if submit, finalTranscript.isEmpty == false {
            completion?(finalTranscript)
        }
    }

    private func stopRecognitionResources() {
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func completeSpeaking(_ utterance: AVSpeechUtterance) {
        guard isSpeaking, activeUtterance === utterance else { return }
        isSpeaking = false
        activeUtterance = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let completion = speechCompletion
        speechCompletion = nil
        completion?()
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        // iOS 17以降のアプリ単位APIでマイク権限を確認する
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission(completionHandler: { granted in
                continuation.resume(returning: granted)
            })
        }
    }
}

extension ChappySpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.completeSpeaking(utterance)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.completeSpeaking(utterance)
        }
    }
}
