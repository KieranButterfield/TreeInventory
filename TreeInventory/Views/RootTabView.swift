//
//  RootTabView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingOnboarding = false

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
        .overlay(alignment: .bottomTrailing) {
            Button {
                showingOnboarding = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary.opacity(0.45))
            }
            .padding(.trailing, 18)
            .padding(.bottom, 72)
            .accessibilityLabel("Open user guide")
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(isPresented: $showingOnboarding)
        }
        .onAppear {
            if !hasSeenOnboarding {
                showingOnboarding = true
                hasSeenOnboarding = true
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
