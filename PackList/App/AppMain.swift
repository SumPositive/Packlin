//  アプリ起動エントリ
//  Firebase、SwiftData、AdMob、共通Environmentの初期化をまとめる
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics
import GoogleMobileAds  // iOSのみ、MacやVisionには対応せずエラーになる

/// Universal Link取込の結果をユーザーへ通知する
private struct PublicPackLinkAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@main
struct AppMain: App {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigationStore = NavigationStore()
    /// ChatGPT生成で利用するクレジット残高。アプリ全体で共有するためStateObject化
    @StateObject private var creditStore: CreditStore
    /// Undo/Redo を自前で管理する履歴サービス
    @StateObject private var historyService = UndoStackService()
    @AppStorage(AppStorageKey.appearanceMode) private var appearanceMode: AppearanceMode = .default
    @AppStorage(AppStorageKey.fontScale) private var fontScale: FontScale = .default
    @AppStorage(AppStorageKey.insertionPosition) private var insertionPosition: InsertionPosition = .default
    @State private var importingPublicPackID: String?
    @State private var pendingPublicPackID: String?
    @State private var importedPublicPackID: String?
    @State private var publicPackLinkAlert: PublicPackLinkAlert?

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
            // 匿名の設定分布を集計し、今後のUI改善判断に使う
            GALogger.log(.settings_snapshot(settings: .current()))
            if let containerError {
                // DB初期化失敗をAnalyticsへ送り、リセット誘導の発生数を把握する
                logError(containerError, domain: "app_model_container_init", message: "ModelContainer初期化失敗")
            }
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
            // 設定の文字サイズを全画面に適用（自動以外は固定の Dynamic Type を強制）
            .appFontScale(fontScale)
            // カスタムURL経由でも同じ公開パック取込処理へ渡す
            .onOpenURL { url in
                handlePublicPackURL(url)
            }
            // Universal Linkから渡されたWeb URLを受け取る
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handlePublicPackURL(url)
            }
            .overlay {
                if importingPublicPackID != nil {
                    // 起動直後の通信中も取込処理中であることを示す
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(Text("public.pack.import"))
                }
            }
            .alert(item: $publicPackLinkAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
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
                // バックグラウンド保存失敗を収集し、データ保持の問題分析に使う
                logError(error, domain: "app_background_save", message: "バックグラウンド保存失敗")
            }
        }

    }

    /// Packlinの公開パック共有URLだけを受け付ける
    private static func publicPackID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "azuki-api.azukid.com" else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
              components[0] == "packlin",
              components[1] == "public",
              let uuid = UUID(uuidString: components[2]) else { return nil }
        return uuid.uuidString.lowercased()
    }

    /// Universal Linkを取込キューへ渡し、同じ通知の二重処理を防ぐ
    @MainActor
    private func handlePublicPackURL(_ url: URL) {
        guard let publishedID = Self.publicPackID(from: url),
              publishedID != importedPublicPackID else { return }

        if let importingPublicPackID {
            if importingPublicPackID != publishedID {
                pendingPublicPackID = publishedID
            }
            return
        }
        startPublicPackImport(publishedID: publishedID)
    }

    /// 公開パックを1件ずつ取り込み、待機中のリンクがあれば続けて処理する
    @MainActor
    private func startPublicPackImport(publishedID: String) {
        importingPublicPackID = publishedID
        Task { @MainActor in
            let succeeded = await importPublicPackFromLink(publishedID: publishedID)
            if succeeded {
                importedPublicPackID = publishedID
            }
            importingPublicPackID = nil

            if let nextID = pendingPublicPackID {
                pendingPublicPackID = nil
                if nextID != importedPublicPackID {
                    startPublicPackImport(publishedID: nextID)
                }
            }
        }
    }

    /// 共有リンクの公開パックを検証してSwiftDataへ保存する
    @MainActor
    private func importPublicPackFromLink(publishedID: String) async -> Bool {
        guard let container = sharedModelContainer else {
            publicPackLinkAlert = PublicPackLinkAlert(
                title: String(localized: "import.failed"),
                message: String(localized: "network.seems.down.please.try.again")
            )
            return false
        }

        do {
            let userID = creditStore.regenerateUserIdIfNeeded()
            let dto = try await AzukiApi.shared.importPublicPack(publishedId: publishedID, userId: userID)
            // Packlin形式以外の応答をローカルDBへ入れない
            guard dto.productName == PACK_JSON_DTO_PRODUCT_NAME,
                  dto.copyright == PACK_JSON_DTO_COPYRIGHT,
                  dto.version == PACK_JSON_DTO_VERSION else {
                throw AzukiAPIError.decoding
            }

            let context = container.mainContext
            // 取込失敗時のロールバックで既存編集を失わないよう先に保存する
            if context.hasChanges {
                try context.save()
            }
            let descriptor = FetchDescriptor<M1Pack>()
            let packs = try context.fetch(descriptor).sorted { $0.order < $1.order }
            let insertionIndex = insertionPosition == .head ? 0 : packs.count
            let newOrder = sparseOrderForInsertion(items: packs, index: insertionIndex) {
                normalizeSparseOrders(packs)
            }
            let importedPack = PackImporter.insertPack(from: dto, into: context, order: newOrder)
            do {
                try context.save()
            } catch {
                // 保存できなかった追加分だけを破棄する
                context.rollback()
                throw error
            }

            let itemCount = dto.groups.reduce(0) { $0 + $1.items.count }
            GALogger.log(.public_pack_result(action: "import_link", isSuccess: true, itemCount: itemCount,
                                             errorDomain: nil, errorCode: nil, message: nil))
            // 一覧へ戻して、取り込んだパックが見える位置まで移動する
            navigationStore.showPackList(packID: importedPack.id)
            let importedMessage = String(localized: "public.pack.imported")
            let message = dto.name.isEmpty ? importedMessage : "\(dto.name)\n\(importedMessage)"
            publicPackLinkAlert = PublicPackLinkAlert(
                title: String(localized: "import.done"),
                message: message
            )
            return true
        } catch {
            let info = publicPackErrorInfo(error)
            GALogger.log(.public_pack_result(action: "import_link", isSuccess: false, itemCount: nil,
                                             errorDomain: info.domain, errorCode: info.code, message: info.message))
            publicPackLinkAlert = PublicPackLinkAlert(
                title: String(localized: "import.failed"),
                message: error.localizedDescription
            )
            return false
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
        let existingPacks: [M1Pack]
        do {
            existingPacks = try context.fetch(descriptor)
        } catch {
            // 初期パック確認失敗をAnalyticsへ送り、初回起動時のDB問題分析に使う
            logError(error, domain: "sample_pack_fetch", message: "初期パック確認失敗")
            return
        }
        guard existingPacks.isEmpty else {
            // M1Packが空でない
            return
        }
        // Bundle サンプル.packlin ファイル
        // ユーザーの優先ローカライズに応じたサンプルを読み込む
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
                // サンプル読み込み失敗をAnalyticsへ送り、同梱データ問題の検知に使う
                logError(error, domain: "sample_pack_load", message: "サンプル読み込み失敗 \(fileName)")
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
                // サンプル保存失敗をAnalyticsへ送り、初期データ投入の問題分析に使う
                logError(error, domain: "sample_pack_save", message: "サンプル保存失敗")
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
