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

    @StateObject private var kb = KeyboardObserver()

    var body: some Scene {
        WindowGroup {
            PackListView()
                .offset(y: -kb.height) // ← アンカー（= このビュー）をキーボード高さぶん持ち上げる
                .animation(.easeOut(duration: 0.5), value: kb.height)
        }
        .modelContainer(sharedModelContainer)

    }
}

