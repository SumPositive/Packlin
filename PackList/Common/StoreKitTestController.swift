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

            // StoreKitTestSession は iOS 16 SDK に含まれる新 API で、古い Xcode（iOS 15 以前の SDK）では型自体が存在しない。
            // そのため互換性を重視し、常に SKTestSession を利用してテストセッションを構築するよう一本化する。
            // Objective-C ブリッジを経由してセッションを生成し、NSException によるクラッシュを防ぐ
            let legacySession = try createLegacySession(configurationURL: configurationURL)
            configureLegacySession(legacySession)
            sessionBox = legacySession
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
#if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
extension StoreKitTestController {
    /// Objective-C ヘルパーを利用して SKTestSession を生成する
    /// - Parameter configurationURL: バンドル内の StoreKit Configuration ファイル URL
    /// - Throws: StoreKitTestBridge 由来の NSError もしくはキャスト失敗エラー
    private func createLegacySession(configurationURL: URL) throws -> SKTestSession {
        var nsError: NSError?
        // CreateSKTestSessionSafely は Objective-C 実装で NSException を握りつぶしたうえで NSError を返してくれる
        guard let rawSession = CreateSKTestSessionSafely(configurationURL as NSURL, &nsError) else {
            if let bridgeError = nsError {
                throw bridgeError
            }
            throw NSError(domain: "StoreKitTestBridge", code: -3, userInfo: [NSLocalizedDescriptionKey: "StoreKitTest セッションを生成できませんでした。"])
        }
        guard let session = rawSession as? SKTestSession else {
            throw NSError(domain: "StoreKitTestBridge", code: -4, userInfo: [NSLocalizedDescriptionKey: "StoreKitTest セッションの型変換に失敗しました。"])
        }
        return session
    }

    /// SKTestSession を初期化する補助関数
    /// - Parameter session: StoreKit Test 専用セッション
    private func configureLegacySession(_ session: SKTestSession) {
        // disableDialogs が利用可能な場合のみ設定する。古い iOS でセレクタが存在しないケースを考慮して responds を確認する。
        if session.responds(to: Selector(("setDisableDialogs:"))) {
            session.disableDialogs = true
        }

        // 旧 API では同期メソッドが提供されているため、そのまま呼び出して全トランザクションを消去する
        session.clearTransactions()
    }
}
#endif
