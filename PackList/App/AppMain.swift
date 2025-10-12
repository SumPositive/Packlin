//
//  AppMain.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import Foundation
import SwiftUI
import SwiftData
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct AppMain: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationPath = NavigationPath()
    /// ChatGPT生成で利用するクレジット残高。アプリ全体で共有するためStateObject化
    @StateObject private var creditStore = CreditStore()
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
        // Migrate： V2-CoreData --> V3-SwiftData
        MigratingFromV2toV3().migrateIfNeeded(modelContainer: sharedModelContainer)

        // M1Packが空ならばサンプルを読み込む
        loadSamplePacksIfNeeded()

        // AdMob
#if canImport(GoogleMobileAds)
        // Initialize the Google Mobile Ads SDK.
        MobileAds.shared.start()
        // Test mode
        let testDeviceIdentifiers = ["2077ef9a63d2b398840261c8221a0c9b"]
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
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
        // Bundle サンプル.pack ファイル
        let sampleFileNames = [
            "Pack_Trip_1N",
            "Pack_Trip_2N",
            "Pack_Fuji_1N",
            "Pack_Travel_1week",
            "Pack_DayHike",
            "Pack_BabyTrip_1N2D",
        ]

        var nextOrder = existingPacks.map { $0.order }.max() ?? -ORDER_SPARSE
        for fileName in sampleFileNames {
            do {
                guard let url = Bundle.main.url(forResource: fileName, withExtension: PACK_FILE_EXTENSION) else { continue }
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
            }
        }
    }

}

