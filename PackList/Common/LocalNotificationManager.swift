//
//  LocalNotificationManager.swift
//  PackList
//
//  Created by OpenAI on 2025/12/03.
//

import Foundation
import UserNotifications
import FirebaseCrashlytics

/// AI生成完了をローカル通知で伝えるための管理クラス
/// UNUserNotificationCenterをラップして、許可確認と通知発行をまとめる役割を持つ
/// 通知のデリゲート機能を扱うためNSObjectを継承する
final class LocalNotificationManager: NSObject {
    /// 生成したマネージャをシングルトンで使い回し、通知センターとのやり取りを一元化する
    static let shared = LocalNotificationManager()

    /// 内部で利用するUNUserNotificationCenterの参照
    private let notificationCenter = UNUserNotificationCenter.current()
    /// 通知許可のリクエスト済みかをUserDefaultsで覚えておく
    private let authorizationRequestedKey = "localNotificationAuthorizationRequested"
    /// UserDefaultsへのアクセスに使う
    private let userDefaults = UserDefaults.standard

    private override init() {
        super.init()
        // アプリが前面にあってもバナーやサウンドを出すため、UNUserNotificationCenterDelegateを自分に設定する
        notificationCenter.delegate = self
    }

    /// AI生成が成功した際にローカル通知を発行する
    /// - Parameter packName: 生成したパックの名称
    func notifyPackGenerationSucceeded(packName: String) async {
        let title = String(localized: "チャッピーの提案が届きました")
        let body = String(localized: "\(packName) を追加しました。アプリで内容を確認しましょう")
        await scheduleNotification(title: title, body: body, suffix: "success")
    }

    /// AI生成が失敗した際にローカル通知を発行する
    /// - Parameter message: 利用者へ伝えたい失敗理由
    func notifyPackGenerationFailed(message: String) async {
        let title = String(localized: "チャッピーからの応答がありません")
        // 失敗理由はダイアログより長くなる場合があるので、通知では要点だけ伝える
        let body = message
        await scheduleNotification(title: title, body: body, suffix: "failure")
    }

    /// 通知許可が未確認ならリクエストし、結果を返す
    private func ensureAuthorization() async -> Bool {
        let settings = await fetchNotificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = await requestAuthorization()
            return granted
        case .denied:
            return false
        default:
            return true
        }
    }

    /// タイトルと本文を指定してローカル通知を登録する共通処理
    /// - Parameters:
    ///   - title: 通知に表示するタイトル
    ///   - body: 通知本文
    ///   - suffix: リクエスト識別子に付与するサフィックス（成功／失敗の区別に利用）
    private func scheduleNotification(title: String, body: String, suffix: String) async {
        // まずは通知許可があるか確認し、未許可ならここで終了
        let authorizationGranted = await ensureAuthorization()
        if authorizationGranted == false {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // すぐに気づけるよう、1秒後に発火するトリガーを用意
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "ai.pack.generated." + suffix + "." + UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await add(request: request)
        } catch {
            // 通知登録に失敗した場合はCrashlyticsへ送信して運用保守に役立てる
            Crashlytics.crashlytics().record(error: error)
        }
    }

    /// 通知設定をasync/awaitで取得する
    private func fetchNotificationSettings() async -> UNNotificationSettings {
        // continuationの型を明示してSwiftコンパイラが迷わないようにし、非同期APIを安全にラップする
        await withCheckedContinuation { (continuation: CheckedContinuation<UNNotificationSettings, Never>) in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    /// 未リクエストの場合のみユーザーへ通知許可を求める
    private func requestAuthorization() async -> Bool {
        if userDefaults.bool(forKey: authorizationRequestedKey) {
            // 既にダイアログを出している場合は再表示しない代わりに最新設定を問い合わせる
            // requestAuthorizationを繰り返さない代わりに、最新設定から許可状態を判定する
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                notificationCenter.getNotificationSettings { settings in
                    let status = settings.authorizationStatus
                    let granted = status == .authorized || status == .provisional || status == .ephemeral
                    continuation.resume(returning: granted)
                }
            }
        }

        let options: UNAuthorizationOptions = [.alert, .sound]
        // 許可ダイアログの結果もContinuationで受け取り、呼び出し元がawaitで扱えるようにする
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            notificationCenter.requestAuthorization(options: options) { accepted, _ in
                continuation.resume(returning: accepted)
            }
        }
        userDefaults.set(true, forKey: authorizationRequestedKey)
        return granted
    }

    /// UNNotificationRequestをasync/awaitで追加する
    private func add(request: UNNotificationRequest) async throws {
        // Voidを返すContinuationであることを明示して型推論の失敗を防ぎ、可読性も高める
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.add(request) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension LocalNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // アプリ起動中（フォアグラウンド）でもバナーとサウンドを見せることで、シートを閉じた後の進捗を確実に伝える
        completionHandler([.banner, .sound, .list])
    }
}

