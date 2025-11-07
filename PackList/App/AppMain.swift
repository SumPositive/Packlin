//
//  AppMain.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftUI
import SwiftData
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct AppMain: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    /// ChatGPT生成で利用するクレジット残高。アプリ全体で共有するためStateObject化
    @StateObject private var creditStore = CreditStore()
    #if canImport(FirebaseCore) || canImport(FirebaseAnalytics) || canImport(FirebaseCrashlytics)
    /// UIテストやシミュレータ・プレビューではFirebase関連初期化を抑止するフラグ
    private let isFirebaseEnabled: Bool
    #endif
    #if canImport(GoogleMobileAds)
    /// UIテストやシミュレータ・プレビューではAdMob初期化を抑止するフラグ
    private let isAdMobEnabled: Bool
    #endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            M1Pack.self,
            M2Group.self,
            M3Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            // Undo/Redo のために UndoManager を設定
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false // 自動イベントグルーピングを無効化する。独自にBegin/Endするため
            container.mainContext.undoManager = undoManager
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // 環境変数を参照し通信系SDK初期化を安全に行える状況か判定する
        let environment = ProcessInfo.processInfo.environment
        let processArguments = ProcessInfo.processInfo.arguments
        // UIテスト実行中はCoreTelephonyサービスが利用できずエラーが多発する
        let isRunningForUITest = environment["XCTestConfigurationFilePath"] != nil
        // Xcode Previewsではバックエンド接続が無効なケースが多い
        let isRunningForPreview = processArguments.contains("XCODE_RUNNING_FOR_PREVIEWS")
        #if targetEnvironment(simulator)
        // シミュレータではCoreTelephonyが未実装でエラーが出る
        let isSimulator = true
        #else
        // targetEnvironmentで検出できないケース（例：SwiftUIプレビュー用ホストアプリ）も環境変数で補完
        let isSimulator = environment["SIMULATOR_UDID"] != nil
        #endif
        // 通信系SDKを利用できない環境かを総合判定する
        let hasConnectivityLimitation = isRunningForUITest || isRunningForPreview || isSimulator
        #if canImport(FirebaseCore) || canImport(FirebaseAnalytics) || canImport(FirebaseCrashlytics)
        // 通信制限環境ではFirebase初期化をスキップしログ出力を抑止する
        self.isFirebaseEnabled = hasConnectivityLimitation == false
        // Firebaseのデフォルトデータ収集フラグを切り替え、自動初期化による通信も止める
        if self.isFirebaseEnabled {
            // 本番時は通常ログレベルを維持
            FirebaseConfiguration.shared.setLoggerLevel(.notice)
        } else {
            // 通信制限環境ではログを最小限に抑えつつ自動送信を禁止
            FirebaseConfiguration.shared.setLoggerLevel(.min)
        }
        // isDataCollectionDefaultEnabledプロパティはFirebaseCoreのバージョン差異で存在しない場合がある
        // 代わりに個別モジュール側で明示的に収集可否を制御する（Analytics等）
        #endif
        #if canImport(GoogleMobileAds)
        // 通信制限環境ではAdMob初期化をスキップする
        self.isAdMobEnabled = hasConnectivityLimitation == false
        #endif
        #if canImport(FirebaseCrashlytics)
        if self.isFirebaseEnabled {
            // 通信可能な環境では通常通りCrashlyticsを有効化
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        } else {
            // Crashlyticsの自動送信を事前に停止
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        }
        #endif
        // Firebase初期化：GoogleService-Info.plistが存在しない場合でも安全に実行する
#if canImport(FirebaseCore)
        if isFirebaseEnabled && FirebaseApp.app() == nil {
            // 初回起動時のみFirebaseAppを構成する
            FirebaseApp.configure()
        }
#endif

        // Analytics：アプリ起動イベントを記録する
#if canImport(FirebaseAnalytics)
        if isFirebaseEnabled {
            // AnalyticsEventAppOpenでアプリ起動を追跡
            Analytics.setAnalyticsCollectionEnabled(true)
            Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)

            GALogger.log(.app_launch)
        } else {
            // 自動収集が無効化されていることを明示的に保証
            Analytics.setAnalyticsCollectionEnabled(false)
        }
#endif

        // Migrate： V2-CoreData --> V3-SwiftData
        MigratingFromV2toV3().migrateIfNeeded(modelContainer: sharedModelContainer)

        // M1Packが空ならばサンプルを読み込む
        loadSamplePacksIfNeeded()

        // AdMob
#if canImport(GoogleMobileAds)
        if isAdMobEnabled {
            // UIテスト外でのみAdMob SDKを初期化する
            MobileAds.shared.start()
            // Test mode
            let testDeviceIdentifiers = ["2077ef9a63d2b398840261c8221a0c9b"]
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigationPath) {
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
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(creditStore)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard oldPhase == .inactive, newPhase == .background else { return }
            // バックになる前
            let context = sharedModelContainer.mainContext
            //if context.hasChanges {
                do {
                    // 変更があればDB保存
                    try context.save()
                    // Undoクリア
                    context.undoManager?.closeAllUndoGroups()
                    context.undoManager?.removeAllActions()
                    // Undo/Redoボタン更新
                    NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
                }
                catch {
                    debugPrint("Failed to context.save: \(error)")
                }
            //}
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
#if canImport(FirebaseCrashlytics)
                if isFirebaseEnabled {
                    // サンプル読み込み失敗をCrashlyticsへ送信
                    Crashlytics.crashlytics().record(error: error)
                }
#endif
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
#if canImport(FirebaseCrashlytics)
                if isFirebaseEnabled {
                    // DB保存失敗をCrashlyticsへ送信
                    Crashlytics.crashlytics().record(error: error)
                }
#endif
            }
        }
    }

}

