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
//            let context = container.mainContext
//            let descriptor = FetchDescriptor<E1Title>()
//            let existing = try context.fetch(descriptor)
//            if existing.isEmpty {
//                let title = E1Title(name: "New Title", note: "新しいPackListのタイトルを追加する")
//                let group = E2Group(name: "New Group", parent: title)
//                _ = E3Item(name: "New Item", parent: group)
//                context.insert(title)
//                try context.save()
//            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

