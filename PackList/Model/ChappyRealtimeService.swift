//
//  チャッピーRealtime音声サービス
//  WebRTCの音声接続とRealtimeイベント、差分ツール呼び出しをまとめる
//

import AVFoundation
import Combine
import Foundation
@preconcurrency import WebRTC

@MainActor
final class ChappyRealtimeService: NSObject, ObservableObject {
    struct ToolCall {
        let callId: String
        let name: String
        let arguments: String
    }

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var isProcessing = false
    @Published private(set) var errorMessage: String?

    var onUserTranscript: ((String) -> Void)?
    var onAssistantTranscript: ((String) -> Void)?
    var onToolCall: ((ToolCall) -> Void)?
    var onResponseCompleted: (() -> Void)?
    var onInsufficientCredits: (() -> Void)?
    var onSessionEnded: (() -> Void)?
    var onError: ((String) -> Void)?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?
    private var sessionLimitTask: Task<Void, Never>?
    private var responseTimeoutTask: Task<Void, Never>?
    private var isAudioSessionActive = false

    /// マイク許可を確認し、SDP交換後にRealtime音声接続を開始する
    func start(exchangeSdp: @escaping (String) async throws -> String) async throws {
        stop()
        errorMessage = nil
        connectionState = .connecting
        guard await requestMicrophonePermission() else {
            connectionState = .failed
            throw ChappyRealtimeError.microphonePermissionRequired
        }
        try configureAudioSession()

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        let peerConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )
        guard let connection = Self.factory.peerConnection(
            with: configuration,
            constraints: peerConstraints,
            delegate: self
        ) else {
            stop()
            throw ChappyRealtimeError.peerConnectionUnavailable
        }
        peerConnection = connection

        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": kRTCMediaConstraintsValueTrue,
                "googAutoGainControl": kRTCMediaConstraintsValueTrue,
                "googNoiseSuppression": kRTCMediaConstraintsValueTrue
            ]
        )
        let source = Self.factory.audioSource(with: audioConstraints)
        let track = Self.factory.audioTrack(with: source, trackId: "packlin-audio")
        audioTrack = track
        connection.add(track, streamIds: ["packlin-stream"])

        let dataConfiguration = RTCDataChannelConfiguration()
        dataConfiguration.isOrdered = true
        guard let channel = connection.dataChannel(
            forLabel: "oai-events",
            configuration: dataConfiguration
        ) else {
            stop()
            throw ChappyRealtimeError.dataChannelUnavailable
        }
        dataChannel = channel
        channel.delegate = self

        let offer = try await createOffer(on: connection)
        try await setLocalDescription(offer, on: connection)
        let answerSdp = try await exchangeSdp(offer.sdp)
        let answer = RTCSessionDescription(type: .answer, sdp: answerSdp)
        try await setRemoteDescription(answer, on: connection)
        try await waitForDataChannelOpen()
        ensureSpeakerOutputIfNeeded()
        connectionState = .connected
        isListening = true
        // 長時間の意図しない接続を止め、サーバー側の課金上限とそろえる
        sessionLimitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
            guard Task.isCancelled == false else { return }
            // 上限終了を画面へ通知し、停止済みなのに会話中表示が残ることを防ぐ
            self?.finishRemoteSession()
        }
    }

    /// ツール適用結果を会話へ戻し、次の自然な応答へつなげる
    func sendToolOutput(callId: String, success: Bool, currentPack: PackJsonDTO?) {
        let result: [String: Any] = [
            "success": success,
            "currentPack": currentPack.map { packDictionary($0) } ?? NSNull()
        ]
        guard let resultData = try? JSONSerialization.data(withJSONObject: result),
              let resultText = String(data: resultData, encoding: .utf8) else {
            return
        }
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": resultText
            ]
        ])
    }

    /// WebRTC接続と音声セッションを終了する
    func stop() {
        sessionLimitTask?.cancel()
        sessionLimitTask = nil
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        audioTrack = nil
        connectionState = .disconnected
        isListening = false
        isSpeaking = false
        isProcessing = false
        deactivateAudioSession()
    }

    private func configureAudioSession() throws {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)
        isAudioSessionActive = true
        // 接続前も受話口ではなく本体スピーカーを既定にする
        try? session.overrideOutputAudioPort(.speaker)
    }

    private func ensureSpeakerOutputIfNeeded() {
        let session = RTCAudioSession.sharedInstance()
        let hasExternalOutput = session.currentRoute.outputs.contains { output in
            output.portType != .builtInReceiver && output.portType != .builtInSpeaker
        }
        guard hasExternalOutput == false else { return }
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        // WebRTCの再構成後に受話口へ戻った場合だけスピーカーへ補正する
        try? session.overrideOutputAudioPort(.speaker)
    }

    private func deactivateAudioSession() {
        guard isAudioSessionActive else { return }
        isAudioSessionActive = false
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.overrideOutputAudioPort(.none)
        try? session.setActive(false)
    }

    private func requestMicrophonePermission() async -> Bool {
        // iOS 18以降のアプリ単位APIでマイク権限を確認する
        await AVAudioApplication.requestRecordPermission()
    }

    private func createOffer(on connection: RTCPeerConnection) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            connection.offer(for: constraints) { offer, error in
                if let offer {
                    continuation.resume(returning: offer)
                } else {
                    continuation.resume(throwing: error ?? ChappyRealtimeError.offerFailed)
                }
            }
        }
    }

    private func setLocalDescription(_ description: RTCSessionDescription,
                                     on connection: RTCPeerConnection) async throws {
        // 戻り値がないWebRTC処理として継続型を固定する
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription,
                                      on connection: RTCPeerConnection) async throws {
        // 戻り値がないWebRTC処理として継続型を固定する
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func waitForDataChannelOpen() async throws {
        // 初回音声が欠けないよう、制御チャネルの開通を短時間だけ待つ
        for _ in 0..<50 {
            if dataChannel?.readyState == .open {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ChappyRealtimeError.dataChannelOpenTimeout
    }

    private func sendEvent(_ value: [String: Any]) {
        guard dataChannel?.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            return
        }
        dataChannel?.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    private func packDictionary(_ pack: PackJsonDTO) -> Any {
        guard let data = try? JSONEncoder().encode(pack),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return value
    }

    private func handleEventData(_ data: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let event = value as? [String: Any],
              let type = event["type"] as? String else {
            return
        }
        switch type {
        case "input_audio_buffer.speech_started":
            responseTimeoutTask?.cancel()
            responseTimeoutTask = nil
            isListening = true
            isSpeaking = false
            isProcessing = false
        case "input_audio_buffer.speech_stopped":
            isListening = false
            isProcessing = true
            startResponseTimeout()
        case "response.created":
            isListening = false
            isProcessing = true
            startResponseTimeout()
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = event["transcript"] as? String,
               transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                onUserTranscript?(transcript)
            }
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            if let transcript = event["transcript"] as? String,
               transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                onAssistantTranscript?(transcript)
            }
        case "response.output_audio.delta", "response.audio.delta":
            responseTimeoutTask?.cancel()
            responseTimeoutTask = nil
            if isSpeaking == false {
                // 実際の再生開始後に変わった出力先もスピーカーへ戻す
                ensureSpeakerOutputIfNeeded()
            }
            isSpeaking = true
            isProcessing = false
        case "response.done":
            responseTimeoutTask?.cancel()
            responseTimeoutTask = nil
            isSpeaking = false
            isProcessing = false
            if isOutputTruncated(event) {
                // 生成上限による未完了文を正常な応答として会話を続けない
                connectionState = .failed
                let message = String(
                    localized: "chappy.voice.response.truncated",
                    defaultValue: "応答が途中で切れました。リトライしますか"
                )
                errorMessage = message
                onResponseCompleted?()
                onError?(message)
                return
            }
            isListening = true
            handleResponseDone(event)
            onResponseCompleted?()
        case "conversation.item.created":
            handleControlItem(event)
        case "error":
            responseTimeoutTask?.cancel()
            responseTimeoutTask = nil
            connectionState = .failed
            errorMessage = String(localized: "chappy.voice.error.retry", defaultValue: "通信に失敗しました。リトライしますか")
            onError?(errorMessage ?? "")
        default:
            break
        }
    }

    private func startResponseTimeout() {
        responseTimeoutTask?.cancel()
        // 応答イベントが失われても考え中のまま残さず、再試行できる状態へ戻す
        responseTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            guard Task.isCancelled == false, let self, self.isProcessing else { return }
            let message = String(
                localized: "chappy.voice.response.timeout",
                defaultValue: "応答がありません。リトライしますか"
            )
            self.connectionState = .failed
            self.errorMessage = message
            self.onError?(message)
        }
    }

    private func handleResponseDone(_ event: [String: Any]) {
        guard let response = event["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]] else {
            return
        }
        for item in output where item["type"] as? String == "function_call" {
            guard let callId = item["call_id"] as? String,
                  let name = item["name"] as? String,
                  let arguments = item["arguments"] as? String else {
                continue
            }
            onToolCall?(ToolCall(callId: callId, name: name, arguments: arguments))
        }
    }

    private func isOutputTruncated(_ event: [String: Any]) -> Bool {
        // Realtimeの未完了理由を確認し、出力上限到達だけを明示的に扱う
        guard let response = event["response"] as? [String: Any],
              response["status"] as? String != "completed",
              let details = response["status_details"] as? [String: Any] else {
            return false
        }
        return details["reason"] as? String == "max_output_tokens"
    }

    private func handleControlItem(_ event: [String: Any]) {
        guard let item = event["item"] as? [String: Any],
              let content = item["content"] as? [[String: Any]] else {
            return
        }
        let hasInsufficientMarker = content.contains { value in
            value["text"] as? String == "[[PACKLIN_INSUFFICIENT_CREDITS]]"
        }
        if hasInsufficientMarker {
            onInsufficientCredits?()
        }
    }

    private func finishRemoteSession() {
        guard connectionState != .disconnected else { return }
        stop()
        onSessionEnded?()
    }
}

extension ChappyRealtimeService: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor [weak self] in
            if dataChannel.readyState == .closed {
                // サーバー終了時も音声セッションを片付けて画面へ反映する
                self?.finishRemoteSession()
            }
        }
    }

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel,
                                didReceiveMessageWith buffer: RTCDataBuffer) {
        Task { @MainActor [weak self] in
            self?.handleEventData(buffer.data)
        }
    }
}

extension ChappyRealtimeService: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didAdd stream: RTCMediaStream) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didRemove stream: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            if newState == .failed {
                self?.connectionState = .failed
                let message = String(localized: "chappy.voice.error.retry", defaultValue: "通信に失敗しました。リトライしますか")
                self?.errorMessage = message
                self?.onError?(message)
            } else if newState == .closed {
                self?.finishRemoteSession()
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didGenerate candidate: RTCIceCandidate) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didOpen dataChannel: RTCDataChannel) {
        Task { @MainActor [weak self] in
            self?.dataChannel = dataChannel
            dataChannel.delegate = self
        }
    }
}

enum ChappyRealtimeError: LocalizedError {
    case microphonePermissionRequired
    case peerConnectionUnavailable
    case dataChannelUnavailable
    case dataChannelOpenTimeout
    case offerFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            return String(localized: "chappy.microphone.permission.required", defaultValue: "音声入力を使うにはマイクの許可が必要です")
        case .peerConnectionUnavailable, .dataChannelUnavailable, .dataChannelOpenTimeout, .offerFailed:
            return String(localized: "chappy.voice.start.failed", defaultValue: "音声入力を開始できませんでした")
        }
    }
}
