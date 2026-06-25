//
//  CaptureTabView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct CaptureTabView: View {
    @Query private var projects: [Project]
    @State private var selectedProject: Project?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Project picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Project", selection: $selectedProject) {
                        Text("Select a project").tag(Optional<Project>.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if let project = selectedProject {
                    NavigationLink(destination: CaptureView(project: project)) {
                        Label("Start Capture", systemImage: "leaf.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Select a project to start capture")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    CaptureTabView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
