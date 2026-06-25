//
//  ContentView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]

    var body: some View {
        NavigationStack {
            List(projects) { project in
                Text(project.name)
            }
            .navigationTitle("Projects")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Project.self, inMemory: true)
}
