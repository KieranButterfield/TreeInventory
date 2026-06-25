//
//  RootTabView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    var body: some View {
        TabView {
            ProjectsView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            MapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
            CaptureTabView()
                .tabItem { Label("Capture", systemImage: "plus.circle.fill") }
            TeamView()
                .tabItem { Label("Team", systemImage: "person.2.fill") }
            ExportSettingsView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
