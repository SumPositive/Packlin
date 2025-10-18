//
//  StoreKitTestController.swift
//  PackList
//
//  Created to enable simulator StoreKit testing.
//

import Foundation

#if canImport(StoreKit)
import StoreKit
#endif

#if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
import StoreKitTest
#endif

/// StoreKitTestSession の構築と保持を担当するユーティリティ
/// - Note: シミュレータ専用の挙動は `DEBUG` かつ `targetEnvironment(simulator)` のときだけ有効化する
actor StoreKitTestController {
    static let shared = StoreKitTestController()

    #if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
    /// StoreKitTestSession を強参照で保持し、ライフタイム中の破棄を防ぐ
    private var session: StoreKitTestSession?
    /// 同期排他のための内部フラグ。初期化が一度だけ走るようにする
    private var isPreparing: Bool = false
    #endif

    /// 購入処理の直前に呼び出し、必要なら StoreKitTestSession を起動する
    func prepareForPurchaseIfNeeded() async {
        #if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
        // 既に準備済みであれば何もしない（重複初期化を避ける）
        if session != nil {
            return
        }
        if isPreparing {
            return
        }
        isPreparing = true
        do {
            // StoreKit Configuration ファイルのURLをバンドルから手動で探し、見つからなければその時点でフォールバックする
            guard let configurationURL = Bundle.main.url(forResource: "PackListStoreKit", withExtension: "storekit") else {
                #if DEBUG
                print("[StoreKitTest] バンドル内に PackListStoreKit.storekit が見つからなかったため、本番StoreKitを利用します")
                #endif
                isPreparing = false
                return
            }
            // Xcode の StoreKit Configuration (.storekit) を読み込み、テスト用セッションを生成
            let newSession = try StoreKitTestSession(configurationFileURL: configurationURL)
            // 課金ダイアログを自動承認し、シミュレータでのテスト効率を高める
            newSession.disableDialogs = true
            newSession.clearTransactions()
            try await newSession.start()
            session = newSession
        } catch {
            // 設定ファイルの欠如や読み込み失敗が起きた場合はログだけに留め、本番フローにフォールバックする
            #if DEBUG
            print("[StoreKitTest] 初期化に失敗しました: \(error)")
            #endif
        }
        isPreparing = false
        #else
        // 実機やリリースビルドではそのまま実ストアに接続するため、何もする必要がない
        return
        #endif
    }
}
