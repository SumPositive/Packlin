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

            // まずは iOS 16 以降の StoreKitTestSession（Swift Concurrency 対応版）を優先し、
            // await での初期化が行える環境ではこちらを採用する。これにより iOS 17 以降で報告されている
            // SKTestSession 利用時の SIGABRT を回避できる。
            if #available(iOS 16.0, *) {
                do {
                    let modernSession = try StoreKitTestSession(configurationFileURL: configurationURL)
                    await configureModernSession(modernSession)
                    sessionBox = modernSession
                    return
                } catch {
                    // 生成に失敗した場合はログを残し、従来 API へのフォールバックに切り替える
                    #if DEBUG
                    print("[StoreKitTest] modern session 構築失敗: \(error)")
                    #endif
                }
            }

            // 上記の条件から外れる場合（iOS 14〜15）は従来の SKTestSession を利用する
            let legacySession = try SKTestSession(contentsOf: configurationURL)
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
    /// StoreKitTestSession（iOS 16 以降）を本テスト環境向けに初期化する
    /// - Parameter session: Swift Concurrency 対応のテストセッション
    @available(iOS 16.0, *)
    private func configureModernSession(_ session: StoreKitTestSession) async {
        // disableDialogs = true で課金ダイアログを抑制し、自動承認ルートに固定する
        session.disableDialogs = true

        do {
            // clearTransactions() は async throws なので await し、残っているテストトランザクションを確実に掃除する
            try await session.clearTransactions()
        } catch {
            // トランザクション消去が失敗しても StoreKitTest の利用自体は継続できるため、DEBUG ログを残して処理を進める
            #if DEBUG
            print("[StoreKitTest] modern clearTransactions でエラー: \(error)")
            #endif
        }
    }

    /// SKTestSession（iOS 14〜15）を初期化する補助関数
    /// - Parameter session: 旧 API 版のテストセッション
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
