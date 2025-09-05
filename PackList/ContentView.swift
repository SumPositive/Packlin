//
//  ContentView.swift
//  PackList
//
//  Created by sumpo on 2025/09/05.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Title.createdAt, order: .reverse)]) private var titles: [Title]

    var body: some View {
        NavigationView {
            List {
                TitleList(titles: titles)
            }
            .listStyle(.plain)
            .navigationTitle("Titles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Title") {
                        addTitle()
                    }
                }
            }
        }
    }

    private func addTitle() {
        let newTitle = Title(name: "New Title")
        modelContext.insert(newTitle)
    }
}

#Preview {
    ContentView()
}

