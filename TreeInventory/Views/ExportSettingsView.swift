//
//  ExportSettingsView.swift
//  TreeInventory
//
//  Created by Kieran Butterfield on 6/25/26.
//

import SwiftUI
import SwiftData
import UIKit

struct ExportSettingsView: View {
    @AppStorage("surveyorName") private var surveyorName: String = ""
    @Query private var projects: [Project]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProject: Project?
    @State private var showingAddProject = false
    @State private var showingSyncAlert = false
    @State private var exportAlert: ExportAlert? = nil
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            Form {
                // Surveyor section
                Section("Surveyor") {
                    TextField("Your name", text: $surveyorName)
                        .autocorrectionDisabled()
                }

                // Export section
                Section("Export") {
                    Picker("Project", selection: $selectedProject) {
                        Text("Select a project").tag(Optional<Project>.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(Optional(project))
                        }
                    }

                    Button {
                        exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(selectedProject == nil)
                }

                // Projects section
                Section("Projects") {
                    ForEach(projects) { project in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.headline)
                                Text("\(project.treeRecords.count) tree\(project.treeRecords.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(project)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showingAddProject = true
                    } label: {
                        Label("Add Project", systemImage: "plus.circle")
                    }
                }

                // Sync section
                Section("Sync") {
                    Button {
                        showingSyncAlert = true
                    } label: {
                        Label("Sync with Supabase", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .navigationTitle("Export & Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAddProject) {
                AddProjectView()
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
            .alert("Sync", isPresented: $showingSyncAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Supabase not configured. Add credentials in a future update.")
            }
            .alert(item: $exportAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message))
            }
        }
    }

    private func exportCSV() {
        guard let project = selectedProject else { return }
        do {
            let url = try CSVExporter.temporaryFileURL(for: project.treeRecords, projectName: project.name)
            shareItems = [url]
            showingShareSheet = true
        } catch {
            exportAlert = ExportAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Helpers

struct ExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    ExportSettingsView()
        .modelContainer(for: [Project.self, TreeRecord.self], inMemory: true)
}
