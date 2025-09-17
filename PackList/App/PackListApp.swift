//
//  PackListApp.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData

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

