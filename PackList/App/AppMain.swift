//
//  AppMain.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

import AppTrackingTransparency
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import GoogleMobileAds  // iOSのみ、MacやVisionには対応せずエラーになる


@main
struct AppMain: App {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigationStore = NavigationStore()
    /// ChatGPT生成で利用するクレジット残高。アプリ全体で共有するためStateObject化
    @StateObject private var creditStore: CreditStore
    /// Undo/Redo を自前で管理する履歴サービス
    @StateObject private var historyService = UndoStackService()
    @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .default

//    /// UIテストやシミュレータ・プレビューではFirebase関連初期化を抑止するフラグ
//    private let isFirebaseEnabled: Bool
//    /// UIテストやシミュレータ・プレビューではAdMob初期化を抑止するフラグ
//    private let isAdMobEnabled: Bool

    // パックが消えた場合は、バックアップから復元してください。
    // ※ 全パックを一括して JSON ファイルにエクスポート／インポートする機能を追加予定。
    var sharedModelContainer: ModelContainer?
    private var containerError: Error?
    /// SQLite ストアファイルの URL（リカバリ時のリネームに使用）
    private let storeURL: URL

    init() {
        // CreditStoreはKeychainに保持されたユーザーIDを元に生成する
        _creditStore = StateObject(wrappedValue: CreditStore())

        // ModelContainer の初期化
        let schema = Schema([
            M1Pack.self,
            M2Group.self,
            M3Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema,
                                                    isStoredInMemoryOnly: false)
        storeURL = modelConfiguration.url
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            containerError = nil
        } catch {
            // 初期化失敗時はエラー画面を表示し、ユーザーがリセットを選択できるようにする
            sharedModelContainer = nil
            containerError = error
        }

        // 実行環境を取得してFirebase初期化の可否を判定する
        let environment = ProcessInfo.processInfo.environment
        let processArguments = ProcessInfo.processInfo.arguments
        let isFirebaseAllowed = Self.shouldEnableFirebase(environment: environment, processArguments: processArguments)
        if isFirebaseAllowed {
            // FirebaseAppが未設定の場合のみ初期化する
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            // 通常ログレベル
            FirebaseConfiguration.shared.setLoggerLevel(.notice)
            // Crashlyticsを有効化
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            // AnalyticsEventAppOpenでアプリ起動を追跡
            Analytics.setAnalyticsCollectionEnabled(true)
            Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
            GALogger.log(.app_launch)
        }

        if let container = sharedModelContainer {
            // Migrate： V2-CoreData --> V3-SwiftData
            MigratingFromV2toV3().migrateIfNeeded(modelContainer: container)
            // M1Packが空ならばサンプルを読み込む
            loadSamplePacksIfNeeded()
        }

        // AdMob SDKを初期化する前に、テスト端末の設定を反映する
        // テスト端末のIDはアンインストールで変わることがあるため、環境変数で上書きできるようにする
        configureAdMobTestDevices()
        // AdMob SDKを初期化する
        MobileAds.shared.start()

//        #if TESTFLIGHT // Scheme "TestFlight" にて定義が有効になる
//            // このデバイスをテストデバイスとして扱う設定
//            // TestFlight時、本番ユニットIDでも「安全にテスト広告」が表示されるが、
//            // AdMobバックエンドは本番としてのSSVフローが動き、Webhook URLにリクエストが飛びテストできる
//            let testDeviceIdentifiers = ["2077ef9a63d2b398840261c8221a0c9b"]
//            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
//        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = sharedModelContainer {
                    NavigationStack(path: $navigationStore.path) {
                        PackListView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                switch destination {
                                case .groupList(let packID):
                                    GroupListScene(packID: packID)
                                case .itemList(let packID, let groupID):
                                    ItemListScene(packID: packID, groupID: groupID)
                                case .itemEdit(let packID, let groupID, let itemID, let sort):
                                    ItemEditScene(packID: packID, groupID: groupID, itemID: itemID, sort: sort)
                                case .itemSortList(let packID, let sort):
                                    ItemSortListScene(packID: packID, sort: sort)
                                }
                            }
                    }
                    .onAppear {
                        // ATT許可ダイアログを表示（UMP/AdMob SDKの要件）
                        // 許可・拒否どちらでも npa=1 固定のため広告動作は変わらない
                        ATTrackingManager.requestTrackingAuthorization { _ in }
                        // ModelContextにHistoryServiceを接続してUndo/Redoを反映させる
                        let context = container.mainContext
                        if let existing = context.undoManager as? UndoStackManager {
                            existing.history = historyService
                        } else {
                            context.undoManager = UndoStackManager(context: context, history: historyService)
                        }
                    }
                    .modelContainer(container)
                } else {
                    DatabaseErrorView(error: containerError) {
                        renameStoreForRecovery()
                    }
                }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
        }
        .environmentObject(creditStore)
        .environmentObject(historyService)
        // NavigationStackのパスを共有し、画面入れ替え制御を全画面で行えるようにする
        .environmentObject(navigationStore)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background,
                  let container = sharedModelContainer else { return }
            // バックグラウンドへ遷移するタイミングでのみ保存処理を試みる
            let context = container.mainContext
            do {
                // アプリ終了に備えて未保存の差分を反映しておく
                if context.hasChanges {
                    try context.save()
                }
            }
            catch {
                debugPrint("Failed to context.save: \(error)")
            }
        }

    }

    /// 破損した SQLite ストアを .bak にリネームし、次回起動時にクリーンな状態で起動できるようにする
    /// - Note: リネーム後はアプリを強制終了する。次回起動時に空のストアが新規作成される。
    private func renameStoreForRecovery() {
        let fm = FileManager.default
        // メインストア (.store → .store.bak)
        let bakURL = storeURL.appendingPathExtension("bak")
        try? fm.moveItem(at: storeURL, to: bakURL)
        // SQLite WAL モードのサイドカーファイルも退避する
        for suffix in ["-shm", "-wal"] {
            let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
            let sidecarBak = URL(fileURLWithPath: bakURL.path + suffix)
            try? fm.moveItem(at: sidecar, to: sidecarBak)
        }
        // リネーム後はアプリを終了して次回起動時にクリーンな状態にする
        exit(0)
    }

    /// M1Packが空ならばサンプルを読み込む
    private func loadSamplePacksIfNeeded() {
        guard let container = sharedModelContainer else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<M1Pack>()
        guard let existingPacks = try? context.fetch(descriptor), existingPacks.isEmpty else {
            // M1Packが空でない
            return
        }
        // Bundle サンプル.packlin ファイル
        // 英語がBaseリソース、ja.lprojが日本語リソース
        let sampleFileNames = [
            "Pack_Trip_1N",
            "Pack_DayHike",
            "Pack_BabyTrip_1N2D",
        ]

        // ユーザーの優先言語と開発言語を優先順位として保持
        var localizationCandidates: [String] = Bundle.main.preferredLocalizations
        if let developmentLocalization = Bundle.main.developmentLocalization {
            // 重複を避けながら開発言語（Base言語）を末尾に追加
            if localizationCandidates.contains(developmentLocalization) == false {
                localizationCandidates.append(developmentLocalization)
            }
        }

        var nextOrder = existingPacks.map { $0.order }.max() ?? -ORDER_SPARSE
        for fileName in sampleFileNames {
            do {
                // 優先言語から順番に該当ローカライズのファイルを探索
                var resourceURL: URL?
                for localization in localizationCandidates {
                    if let localizedURL = Bundle.main.url(forResource: fileName,
                                                           withExtension: PACK_FILE_EXTENSION,
                                                           subdirectory: nil,
                                                           localization: localization) {
                        resourceURL = localizedURL
                        break
                    }
                }
                // ローカライズが見つからない場合はBaseリソースを使用
                if resourceURL == nil {
                    resourceURL = Bundle.main.url(forResource: fileName, withExtension: PACK_FILE_EXTENSION)
                }

                guard let url = resourceURL else { continue }
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let dto = try decoder.decode(PackJsonDTO.self, from: data)

                // チェック & Migration
                guard dto.productName == PACK_JSON_DTO_PRODUCT_NAME,
                      dto.copyright == PACK_JSON_DTO_COPYRIGHT,
                      dto.version == PACK_JSON_DTO_VERSION else { continue }

                // Pack行
                nextOrder += ORDER_SPARSE
                // PackJsonDTO をDBへインポートする
                PackImporter.insertPack(from: dto, into: context, order: nextOrder)
            } catch {
                debugPrint("Failed to load sample pack \(fileName): \(error)")
                // サンプル読み込み失敗をCrashlyticsへ送信
                Crashlytics.crashlytics().record(error: error)
            }
        }

        if context.hasChanges {
            do {
                // DB保存
                try context.save()
                // Undoクリア
                context.undoManager?.closeAllUndoGroups()
                context.undoManager?.removeAllActions()
            } catch {
                debugPrint("Failed to save sample packs: \(error)")
                // DB保存失敗をCrashlyticsへ送信
                Crashlytics.crashlytics().record(error: error)
            }
        }
    }

    /// AdMobテスト端末のIDを環境変数から読み込み、必要なら設定する
    /// - Note: ADMOB_TEST_DEVICE_IDS="id1,id2" のように指定する
    private func configureAdMobTestDevices() {
        // シミュレータはGoogle提供の固定IDを使う
        var testDeviceIdentifiers: [String] = []
        #if targetEnvironment(simulator)
        testDeviceIdentifiers.append("SIMULATOR")
        #endif

        // 環境変数から追加のIDを取り込む（カンマ区切り）
        if let rawIdentifiers = ProcessInfo.processInfo.environment["ADMOB_TEST_DEVICE_IDS"] {
            let extraIdentifiers = rawIdentifiers
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            testDeviceIdentifiers.append(contentsOf: extraIdentifiers)
        }

        // 空なら設定しない（本番配信時の挙動を維持）
        if testDeviceIdentifiers.isEmpty == false {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
        }
    }


}

extension AppMain {
    /// Firebaseなどの通信系SDKを安全に初期化できるか判定するヘルパー
    static func shouldEnableFirebase(environment: [String: String], processArguments: [String]) -> Bool {
        // UIテスト中は通信系SDKを抑止する
        let isRunningForUITest = environment["XCTestConfigurationFilePath"] != nil
        // Xcode Previewsはネットワークを伴う処理が利用できないことが多い
        let isRunningForPreview = processArguments.contains("XCODE_RUNNING_FOR_PREVIEWS")
        #if targetEnvironment(simulator)
        // シミュレータでは未実装APIが多くエラーを誘発するため無効化
        let isSimulator = true
        #else
        let isSimulator = environment["SIMULATOR_UDID"] != nil
        #endif
        // いずれかの制限がある場合は初期化を避ける
        let hasLimitation = isRunningForUITest || isRunningForPreview || isSimulator
        return hasLimitation == false
    }
}
