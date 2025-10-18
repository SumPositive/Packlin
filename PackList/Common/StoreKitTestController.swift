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

#if canImport(StoreKitTest)
import StoreKitTest
#endif

/// StoreKit のテストセッション（SKTestSession）を構築・保持するユーティリティ
/// - Note: シミュレータ専用の挙動は `DEBUG` かつ `targetEnvironment(simulator)` のときだけ有効化する
actor StoreKitTestController {
    static let shared = StoreKitTestController()

    #if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
    /// SKTestSession を強参照で保持し、テスト用セッションが途中で解放されないようにする
    /// - Note: AnyObject として保持することで、対象 OS のバージョン条件に左右されずビルドエラーを避ける
    private var sessionBox: AnyObject?
    /// 同期排他のための内部フラグ。初期化が一度だけ走るようにする
    private var isPreparing: Bool = false
    #endif

    /// 購入処理の直前に呼び出し、必要なら StoreKit のテストセッションを起動する
    func prepareForPurchaseIfNeeded() async {
        #if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
        // iOS 14 以上でのみ StoreKit のテストセッション API が利用可能なので、ランタイム条件を満たさない場合は早期リターンする
        guard #available(iOS 14.0, *) else {
            return
        }
        // 既に準備済みであれば何もしない（重複初期化を避ける）
        if sessionBox != nil {
            return
        }
        if isPreparing {
            return
        }
        isPreparing = true
        defer {
            // 初期化処理が完了したタイミングでフラグを戻し、次の呼び出しに備える
            isPreparing = false
        }
        do {
            // StoreKit Configuration ファイルのURLをバンドルから手動で探し、見つからなければその時点でフォールバックする
            guard let configurationURL = Bundle.main.url(forResource: "PackListStoreKit", withExtension: "storekit") else {
                #if DEBUG
                print("[StoreKitTest] バンドル内に PackListStoreKit.storekit が見つからなかったため、本番StoreKitを利用します")
                #endif
                return
            }
            // iOS16 以降では StoreKitTestSession を用い、それ以前では SKTestSession を利用する
            if #available(iOS 16.0, *) {
                // StoreKitTestSession は async API を持つので await 付きで初期化・後処理を行う
                let newSession = try StoreKitTestSession(configurationFileURL: configurationURL)
                // 課金ダイアログを自動承認し、ユーザー操作なしでフローを通過できるようにする
                newSession.disableDialogs = true
                // 非同期APIなので await を付け、未消化トランザクションを必ず初期化前に掃除する
                try await newSession.clearTransactions()
                // AnyObject へ代入してライフタイムを保持する
                sessionBox = newSession
            } else {
                // 旧 OS では SKTestSession を利用して同様の初期化を行う
                let legacySession = try SKTestSession(configurationFileURL: configurationURL)
                legacySession.disableDialogs = true
                try legacySession.clearTransactions()
                sessionBox = legacySession
            }
        } catch {
            // 設定ファイルの欠如や読み込み失敗が起きた場合はログだけに留め、本番フローにフォールバックする
            #if DEBUG
            print("[StoreKitTest] 初期化に失敗しました: \(error)")
            #endif
        }
        #else
        // 実機や StoreKitTest を利用できないビルド構成ではそのまま実ストアに接続する
        return
        #endif
    }
}
