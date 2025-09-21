//
//  PackListApp.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct PackListApp: App {
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

    }
}

