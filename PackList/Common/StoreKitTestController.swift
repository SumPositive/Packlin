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
// MARK: - StoreKitTest モジュールのインポートについて
// DEBUG ビルドでは Xcode プロジェクトに StoreKitTest.framework を弱リンクとして追加しているため、
// canImport(StoreKitTest) が true になり以下の import が成立する。実機ビルド時はフレームワークが
// 取り除かれるので、この条件付き import 自体がビルドから外れ StoreKit 本番経路のみが利用される。
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
            // Xcode や iOS のバージョンによっては StoreKitTestSession クラスが存在せずコンパイルが失敗するため
            // ここでは互換性の高い SKTestSession のみを利用する。iOS 16 以降では clearTransactions が非同期化
            // されているが、Objective-C ランタイム経由で同期 API も残されているため、従来通りの呼び出しで両対応する。
            // SKTestSession の初期化子は contentsOf: をラベルに取るため、URL を直接渡してセッションを生成する
            let session = try SKTestSession(contentsOf: configurationURL)
            session.disableDialogs = true

            // clearTransactions() は iOS16 以降で async throws に拡張されたが、同期版の API も互換のため
            // 依然として利用できる。ビルド環境ごとに挙動が異なっても例外を握りつぶしてフォールバックできるようにする。
            do {
                try session.clearTransactions()
            } catch {
                // 万が一失敗しても購入テスト自体は進められるよう、DEBUG ビルドでログ出力のみ行う
                #if DEBUG
                print("[StoreKitTest] clearTransactions でエラーが発生しました: \(error)")
                #endif
            }
            sessionBox = session
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
