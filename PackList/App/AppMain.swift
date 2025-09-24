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
    @StateObject private var navigationCoordinator = NavigationCoordinator()
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
            container.mainContext.undoManager = UndoManager()
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
            NavigationStack(path: $navigationCoordinator.path) {
                PackListView()
                    .environmentObject(navigationCoordinator)
                    .navigationDestination(for: AppDestination.self) { destination in
                        switch destination {
                        case .groupList(let packID):
                            GroupListScene(packID: packID)
                        case .itemList(let packID, let groupID):
                            ItemListScene(packID: packID, groupID: groupID)
                        }
                    }
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { newPhase, oldPhase in
            guard newPhase == .inactive || newPhase == .background else { return }
            // バックになる前
            let context = sharedModelContainer.mainContext
            if context.hasChanges {
                // 変更があればDB保存
                try? context.save()
            }
            // Undoクリア
            context.undoManager?.removeAllActions()
            NotificationCenter.default.post(name: .updateUndoRedo, object: nil)
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
        // Bundle サンプル.json ファイル
        let sampleFileNames = [
            "Pack_sample1",
            "Pack_sample2"
        ]

        var nextOrder = existingPacks.map { $0.order }.max() ?? -1
        for fileName in sampleFileNames {
            do {
                guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else { continue }
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let dto = try decoder.decode(PackJsonDTO.self, from: data)

                // チェック & Migration
                guard dto.copyright == PACK_JSON_DTO_COPYRIGHT,
                      dto.version == PACK_JSON_DTO_VERSION else { continue }

                // Pack行
                nextOrder += 1
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
                context.undoManager?.removeAllActions()
            } catch {
                debugPrint("Failed to save sample packs: \(error)")
            }
        }
    }
}

