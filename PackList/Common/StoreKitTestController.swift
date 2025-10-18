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

    #if DEBUG && targetEnvironment(simulator)
    /// SKTestSession を強参照で保持し、テスト用セッションが途中で解放されないようにする
    /// - Note: AnyObject として保持することで、対象 OS のバージョン条件に左右されずビルドエラーを避ける
    private var sessionBox: AnyObject?
    /// 同期排他のための内部フラグ。初期化が一度だけ走るようにする
    private var isPreparing: Bool = false
    #endif

    /// 購入処理の直前に呼び出し、必要なら StoreKit のテストセッションを起動する
    func prepareForPurchaseIfNeeded() async {
        #if DEBUG && targetEnvironment(simulator)
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
            // StoreKit の SKTestSession を介してシミュレータ用のテストセッションを生成する
            // - Note: 生成時点でセッションが開始されるため、StoreKitTestSession のような start() 呼び出しは不要
            let newSession = try SKTestSession(configurationFileURL: configurationURL)
            // 課金ダイアログを自動承認し、ユーザー操作なしでフローを通過できるようにする
            newSession.disableDialogs = true
            // 既存のテストトランザクションをリセットし、常にクリーンな状態から検証できるようにする
            try newSession.clearTransactions()
            // AnyObject へ代入してライフタイムを保持する
            sessionBox = newSession
        } catch {
            // 設定ファイルの欠如や読み込み失敗が起きた場合はログだけに留め、本番フローにフォールバックする
            #if DEBUG
            print("[StoreKitTest] 初期化に失敗しました: \(error)")
            #endif
        }
        #else
        // 実機やリリースビルドではそのまま実ストアに接続するため、何もする必要がない
        return
        #endif
    }
}
