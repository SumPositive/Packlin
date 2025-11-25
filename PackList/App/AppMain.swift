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

import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import GoogleMobileAds


@main
struct AppMain: App {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigationStore = NavigationStore()
    /// ChatGPT生成で利用するクレジット残高。アプリ全体で共有するためStateObject化
    @StateObject private var creditStore = CreditStore()
    /// Undo/Redo を自前で管理する履歴サービス
    @StateObject private var historyService = UndoStackService()

//    /// UIテストやシミュレータ・プレビューではFirebase関連初期化を抑止するフラグ
//    private let isFirebaseEnabled: Bool
//    /// UIテストやシミュレータ・プレビューではAdMob初期化を抑止するフラグ
//    private let isAdMobEnabled: Bool

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            M1Pack.self,
            M2Group.self,
            M3Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema,
                                                    isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Firebase初期化
        FirebaseApp.configure()
        // 通常ログレベル
        FirebaseConfiguration.shared.setLoggerLevel(.notice)
        // Crashlyticsを有効化
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        // AnalyticsEventAppOpenでアプリ起動を追跡
        Analytics.setAnalyticsCollectionEnabled(true)
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
        GALogger.log(.app_launch)

        // Migrate： V2-CoreData --> V3-SwiftData
        MigratingFromV2toV3().migrateIfNeeded(modelContainer: sharedModelContainer)

        // M1Packが空ならばサンプルを読み込む
        loadSamplePacksIfNeeded()

        // AdMob SDKを初期化する
        MobileAds.shared.start()
        // Test mode
        let testDeviceIdentifiers = ["2077ef9a63d2b398840261c8221a0c9b"]
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
    }

    var body: some Scene {
        WindowGroup {
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
                                // NavigationTransitionにフェードは存在しないため、アニメーションを打ち消すidentityを適用する
                                // 画面差し替え時のフェードはItemSortList側のwithAnimationで担保する
                                .navigationTransition(.identity)
                        }
                    }
            }
            .onAppear {
                // ModelContextにHistoryServiceを接続してUndo/Redoを反映させる
                let context = sharedModelContainer.mainContext
                if let existing = context.undoManager as? UndoStackManager {
                    existing.history = historyService
                } else {
                    context.undoManager = UndoStackManager(context: context, history: historyService)
                }
            }
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(creditStore)
        .environmentObject(historyService)
        // NavigationStackのパスを共有し、画面入れ替え制御を全画面で行えるようにする
        .environmentObject(navigationStore)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            // バックグラウンドへ遷移するタイミングでのみ保存処理を試みる
            let context = sharedModelContainer.mainContext
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

    /// M1Packが空ならばサンプルを読み込む
    private func loadSamplePacksIfNeeded() {
        let context = sharedModelContainer.mainContext
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

}

//extension AppMain {
//    /// Firebaseなどの通信系SDKを安全に初期化できるか判定するヘルパー
//    static func shouldEnableFirebase(environment: [String: String], processArguments: [String]) -> Bool {
//        // UIテスト中は通信系SDKを抑止する
//        let isRunningForUITest = environment["XCTestConfigurationFilePath"] != nil
//        // Xcode Previewsはネットワークを伴う処理が利用できないことが多い
//        let isRunningForPreview = processArguments.contains("XCODE_RUNNING_FOR_PREVIEWS")
//        #if targetEnvironment(simulator)
//        // シミュレータでは未実装APIが多くエラーを誘発するため無効化
//        let isSimulator = true
//        #else
//        let isSimulator = environment["SIMULATOR_UDID"] != nil
//        #endif
//        // いずれかの制限がある場合は初期化を避ける
//        let hasLimitation = isRunningForUITest || isRunningForPreview || isSimulator
//        return hasLimitation == false
//    }
//}

