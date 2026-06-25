//
//  TeamView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData

struct TeamView: View {
    @Query private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var showingSyncAlert = false

    private var sortedRecords: [TreeRecord] {
        (selectedProject?.treeRecords ?? []).sorted { $0.timestamp > $1.timestamp }
    }

    private var surveyorCount: Int {
        Set(sortedRecords.map { $0.surveyorName }.filter { !$0.isEmpty }).count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Project picker
                Picker("Project", selection: $selectedProject) {
                    Text("Select a project").tag(Optional<Project>.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if selectedProject == nil {
                    ContentUnavailableView(
                        "No Project Selected",
                        systemImage: "person.2",
                        description: Text("Choose a project to view team activity.")
                    )
                } else {
                    List {
                        // Summary header
                        Section {
                            HStack {
                                Label(
                                    "\(sortedRecords.count) tree\(sortedRecords.count == 1 ? "" : "s") measured",
                                    systemImage: "leaf.fill"
                                )
                                Spacer()
                                Label(
                                    "\(surveyorCount) surveyor\(surveyorCount == 1 ? "" : "s")",
                                    systemImage: "person.2.fill"
                                )
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        // Activity list
                        Section("Recent Activity") {
                            ForEach(sortedRecords) { record in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(record.treeId.isEmpty ? "(no ID)" : record.treeId)
                                                .font(.headline)
                                            if !record.siteCode.isEmpty {
                                                Text(record.siteCode)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        if !record.surveyorName.isEmpty {
                                            Label(record.surveyorName, systemImage: "person.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        // Condition pill
                                        HStack(spacing: 3) {
                                            Circle()
                                                .fill(record.condition.color)
                                                .frame(width: 7, height: 7)
                                            Text(record.condition.label)
                                                .font(.caption2)
                                                .foregroundStyle(record.condition.color)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(record.condition.color.opacity(0.12), in: Capsule())

                                        HStack(spacing: 2) {
                                            Text(record.timestamp, style: .relative)
                                            Text("ago")
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if selectedProject != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingSyncAlert = true
                        } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .alert("Sync", isPresented: $showingSyncAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Supabase not configured yet.")
            }
        }
    }
}

#Preview {
    TeamView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
